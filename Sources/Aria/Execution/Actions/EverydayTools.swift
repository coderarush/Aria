import Foundation
import AppKit

// MARK: - Timers

/// Owns Aria's named countdown timers. Firing posts a system notification (and
/// the notification sound informs even when Aria is quiet). Pure parsing and
/// formatting are static so they're testable without scheduling anything.
actor TimerCenter {
    static let shared = TimerCenter()

    struct ActiveTimer {
        let id: UUID
        let label: String
        let endsAt: Date
        let task: Task<Void, Never>
    }

    private var timers: [UUID: ActiveTimer] = [:]
    /// Injectable for tests; the default posts a notification.
    private let onFire: @Sendable (String) -> Void

    init(onFire: @escaping @Sendable (String) -> Void = { label in
        Notifier.notify(title: "Timer done", body: label)
    }) {
        self.onFire = onFire
    }

    /// Parse "10 minutes", "90 sec", "1.5h", "2:30" (min:sec) → seconds.
    static func parseDuration(_ text: String) -> TimeInterval? {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        // "M:SS" → minutes:seconds
        if t.contains(":") {
            let parts = t.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2, parts[1] < 60 else { return nil }
            return parts[0] * 60 + parts[1]
        }
        let number = t.prefix { "0123456789.".contains($0) }
        guard let value = Double(number), value > 0 else { return nil }
        let unit = t.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        switch unit {
        case "", "m", "min", "mins", "minute", "minutes": return value * 60
        case "s", "sec", "secs", "second", "seconds": return value
        case "h", "hr", "hrs", "hour", "hours": return value * 3600
        default: return nil
        }
    }

    /// "2h 5m", "12m", "45s" — for list output and confirmations.
    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 {
            let m = (s % 3600) / 60
            return m == 0 ? "\(s / 3600)h" : "\(s / 3600)h \(m)m"
        }
        if s >= 60 {
            let r = s % 60
            return r == 0 ? "\(s / 60)m" : "\(s / 60)m \(r)s"
        }
        return "\(s)s"
    }

    @discardableResult
    func start(seconds: TimeInterval, label: String, now: Date = Date()) -> ActiveTimer {
        let id = UUID()
        let endsAt = now.addingTimeInterval(seconds)
        let fire = onFire
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            fire(label)
            await self?.remove(id)
        }
        let timer = ActiveTimer(id: id, label: label, endsAt: endsAt, task: task)
        timers[id] = timer
        return timer
    }

    func list(now: Date = Date()) -> [String] {
        timers.values
            .sorted { $0.endsAt < $1.endsAt }
            .map { "\($0.label) — \(Self.format($0.endsAt.timeIntervalSince(now))) left" }
    }

    /// Cancel by (case-insensitive) label substring, or everything when nil.
    /// Returns how many were cancelled.
    func cancel(matching label: String?) -> Int {
        let victims = timers.values.filter { timer in
            guard let label, !label.isEmpty else { return true }
            return timer.label.lowercased().contains(label.lowercased())
        }
        for v in victims {
            v.task.cancel()
            timers[v.id] = nil
        }
        return victims.count
    }

    private func remove(_ id: UUID) { timers[id] = nil }

    var count: Int { timers.count }
}

/// "Set a timer for 10 minutes" / "how long left" / "cancel the pasta timer".
struct TimerTool: AriaTool {
    static let name = "timer"
    static let description = "Start, list, or cancel named countdown timers. Input: {action: start|list|cancel, duration: e.g. '10 minutes' (for start), label: optional name like 'pasta'}. When the timer ends the user gets a notification."
    static let paramHints: [String: String] = [
        "action": "start | list | cancel",
        "duration": "For start: '10 minutes', '90 seconds', '1.5 hours'",
        "label": "Optional timer name, e.g. 'pasta'"
    ]

    private let center: TimerCenter

    init(center: TimerCenter = .shared) {
        self.center = center
    }

    func run(input: [String: String]) async throws -> ToolResult {
        let action = input["action"]?.lowercased() ?? "start"
        switch action {
        case "start":
            guard let raw = input["duration"],
                  let seconds = TimerCenter.parseDuration(raw) else {
                return .fail("Missing input: duration (e.g. '10 minutes').")
            }
            let label = input["label"]?.trimmingCharacters(in: .whitespaces)
            let name = (label?.isEmpty == false) ? label! : "\(TimerCenter.format(seconds)) timer"
            await center.start(seconds: seconds, label: name)
            return .ok("Timer “\(name)” set — I'll notify you in \(TimerCenter.format(seconds)).")
        case "list":
            let lines = await center.list()
            return .ok(lines.isEmpty ? "No timers running." : lines.joined(separator: "\n"))
        case "cancel":
            let n = await center.cancel(matching: input["label"])
            return .ok(n == 0 ? "No matching timer found."
                              : "Cancelled \(n) timer\(n == 1 ? "" : "s").")
        default:
            return .fail("Unknown action “\(action)” — use start, list, or cancel.")
        }
    }
}

// MARK: - Weather

/// Open-Meteo current conditions + today's range. Free, no API key, so this
/// works out of the box. Remembers the last place so "what's the weather"
/// needs no argument the second time.
struct WeatherTool: AriaTool {
    static let name = "weather"
    static let description = "Current weather + today's forecast for a place. Input: {place: city name, e.g. 'San Francisco'}. Omit place to reuse the last one asked about."
    static let paramHints: [String: String] = [
        "place": "City or town name; omitted = last place used"
    ]

    static let lastPlaceKey = "weather.lastPlace"

    func run(input: [String: String]) async throws -> ToolResult {
        var place = input["place"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if place.isEmpty {
            place = UserDefaults.standard.string(forKey: Self.lastPlaceKey) ?? ""
        }
        guard !place.isEmpty else {
            return .fail("Missing input: place — which city should I check?")
        }

        guard let geo = try await Self.geocode(place) else {
            return .fail("I couldn't find a place called “\(place)”.")
        }
        UserDefaults.standard.set(geo.label, forKey: Self.lastPlaceKey)

        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(geo.lat)),
            .init(name: "longitude", value: String(geo.lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let summary = Self.summarize(place: geo.label, forecastJSON: data) else {
            return .fail("Weather service returned something I couldn't read.")
        }
        return .ok(summary)
    }

    struct Geo { let lat: Double; let lon: Double; let label: String }

    static func geocode(_ place: String) async throws -> Geo? {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: place), .init(name: "count", value: "1")]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (obj["results"] as? [[String: Any]])?.first,
              let lat = first["latitude"] as? Double,
              let lon = first["longitude"] as? Double else { return nil }
        let name = first["name"] as? String ?? place
        let admin = first["admin1"] as? String
        let country = first["country_code"] as? String
        let label = [name, admin ?? country].compactMap { $0 }.joined(separator: ", ")
        return Geo(lat: lat, lon: lon, label: label)
    }

    /// Pure formatter (testable offline): forecast JSON → one spoken-friendly line.
    static func summarize(place: String, forecastJSON: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: forecastJSON) as? [String: Any],
              let current = obj["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double else { return nil }
        let feels = current["apparent_temperature"] as? Double
        let wind = current["wind_speed_10m"] as? Double
        let humidity = current["relative_humidity_2m"] as? Int
        let code = current["weather_code"] as? Int ?? -1

        var line = "\(place): \(Self.describe(code: code)), \(Int(temp.rounded()))°"
        if let feels, abs(feels - temp) >= 2 { line += " (feels \(Int(feels.rounded()))°)" }
        if let daily = obj["daily"] as? [String: Any],
           let highs = daily["temperature_2m_max"] as? [Double], let high = highs.first,
           let lows = daily["temperature_2m_min"] as? [Double], let low = lows.first {
            line += ". Today \(Int(low.rounded()))°–\(Int(high.rounded()))°"
            if let rains = daily["precipitation_probability_max"] as? [Int],
               let rain = rains.first, rain >= 20 {
                line += ", \(rain)% chance of rain"
            }
        }
        if let humidity { line += ". Humidity \(humidity)%" }
        if let wind { line += ", wind \(Int(wind.rounded())) km/h" }
        return line + "."
    }

    /// WMO weather codes → plain words.
    static func describe(code: Int) -> String {
        switch code {
        case 0: return "clear"
        case 1: return "mostly clear"
        case 2: return "partly cloudy"
        case 3: return "overcast"
        case 45, 48: return "foggy"
        case 51, 53, 55: return "drizzling"
        case 56, 57: return "freezing drizzle"
        case 61, 63, 65: return "raining"
        case 66, 67: return "freezing rain"
        case 71, 73, 75, 77: return "snowing"
        case 80, 81, 82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95: return "thunderstorms"
        case 96, 99: return "thunderstorms with hail"
        default: return "unsettled"
        }
    }
}

// MARK: - Music

/// Direct transport control for Apple Music / Spotify via Apple events —
/// deliberate verbs instead of asking the model to write AppleScript each time.
struct MusicTool: AriaTool {
    static let name = "music_control"
    static let description = "Control music playback: play, pause, next, previous, or 'current' (what's playing). Input: {action: play|pause|next|previous|current, player: optional 'music' (Apple Music, default) or 'spotify'}."
    static let paramHints: [String: String] = [
        "action": "play | pause | next | previous | current",
        "player": "Optional: music (default) | spotify"
    ]

    private let runner = ScriptRunner()

    func run(input: [String: String]) async throws -> ToolResult {
        let action = input["action"]?.lowercased() ?? "current"
        let player = (input["player"]?.lowercased() == "spotify") ? "Spotify" : "Music"

        let script: String
        switch action {
        case "play": script = "tell application \"\(player)\" to play"
        case "pause": script = "tell application \"\(player)\" to pause"
        case "next": script = "tell application \"\(player)\" to next track"
        case "previous", "prev", "back": script = "tell application \"\(player)\" to previous track"
        case "current", "now", "nowplaying":
            script = """
            tell application "\(player)"
                if player state is playing then
                    return (get name of current track) & " — " & (get artist of current track)
                else
                    return "nothing playing"
                end if
            end tell
            """
        default:
            return .fail("Unknown action “\(action)” — use play, pause, next, previous, or current.")
        }

        let out = try await runner.run(code: script, language: .applescript, timeout: 10)
        guard out.success else {
            let hint = out.stderr.contains("-1743")
                ? " (Automation permission for \(player) may be needed — System Settings → Privacy & Security → Automation.)"
                : ""
            return .fail("Couldn't control \(player).\(hint)", diagnostics: out.stderr)
        }
        let text = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "current", "now", "nowplaying":
            return .ok(text == "nothing playing" ? "Nothing is playing in \(player)."
                                                 : "Now playing: \(text)")
        default:
            return .ok("Done — \(action) in \(player).")
        }
    }
}

// MARK: - System status

/// Battery / disk / uptime / thermal in one glance — "how's my Mac doing?"
struct SystemStatusTool: AriaTool {
    static let name = "system_status"
    static let description = "Report the Mac's battery level & charging state, free disk space, uptime, and thermal state. No input."

    func run(input: [String: String]) async throws -> ToolResult {
        var lines: [String] = []
        if let battery = Self.batteryLine() { lines.append(battery) }
        if let disk = Self.diskLine() { lines.append(disk) }
        lines.append(Self.uptimeLine())
        lines.append(Self.thermalLine())
        return .ok(lines.joined(separator: "\n"))
    }

    static func batteryLine() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "batt"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parseBattery(out)
    }

    /// Pure (testable): pmset output → "Battery 84%, charging" or nil on desktops.
    static func parseBattery(_ pmsetOutput: String) -> String? {
        guard let match = pmsetOutput.range(of: #"(\d+)%"#, options: .regularExpression) else {
            return nil
        }
        let percent = pmsetOutput[match].dropLast()
        let state: String
        if pmsetOutput.contains("discharging") { state = "on battery" }
        else if pmsetOutput.contains("charging") { state = "charging" }
        else if pmsetOutput.contains("charged") { state = "fully charged" }
        else { state = "on AC power" }
        return "Battery \(percent)%, \(state)."
    }

    static func diskLine() -> String? {
        guard let attrs = try? FileManager.default
            .attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64,
              let total = attrs[.systemSize] as? Int64, total > 0 else { return nil }
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return "Disk: \(fmt.string(fromByteCount: free)) free of \(fmt.string(fromByteCount: total))."
    }

    static func uptimeLine() -> String {
        let up = Int(ProcessInfo.processInfo.systemUptime)
        let days = up / 86_400, hours = (up % 86_400) / 3600, minutes = (up % 3600) / 60
        if days > 0 { return "Uptime: \(days)d \(hours)h." }
        if hours > 0 { return "Uptime: \(hours)h \(minutes)m." }
        return "Uptime: \(minutes)m."
    }

    static func thermalLine() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Thermals: cool — fans quiet."
        case .fair: return "Thermals: warm but fine."
        case .serious: return "Thermals: hot — heavy load right now."
        case .critical: return "Thermals: critical — something is pinning the machine."
        @unknown default: return "Thermals: unknown."
        }
    }
}

// MARK: - Clipboard history

/// Read back the last few things copied — "what did I copy earlier?" Backed by
/// the ClipboardContext ring that already powers ambient context.
struct ClipboardHistoryTool: AriaTool {
    static let name = "clipboard_history"
    static let description = "List the last few items the user copied to the clipboard (most recent first). No input. Use when the user asks about something they copied."

    func run(input: [String: String]) async throws -> ToolResult {
        let items = await ClipboardContext.shared.history
        guard !items.isEmpty else { return .ok("Clipboard history is empty so far this session.") }
        let lines = items.enumerated().map { i, item -> String in
            let preview = item.count > 200 ? String(item.prefix(200)) + "…" : item
            return "\(i + 1). \(preview.replacingOccurrences(of: "\n", with: " ⏎ "))"
        }
        return .ok(lines.joined(separator: "\n"))
    }
}
