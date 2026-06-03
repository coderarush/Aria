import Foundation

/// Bridge between Friday on the Mac and a Raspberry Pi smart mirror over a local
/// WebSocket. The mirror sends transcripts; the Mac processes and returns
/// responses for the mirror to display.
///
/// STUB ONLY — architected now, implemented later. The smart-mirror integration
/// is not built yet; these methods are intentionally no-ops with TODOs so the
/// rest of the app can wire against a stable interface.
final class MirrorBridge {

    enum ConnectionState: String {
        case notConnected = "Not connected"
        case connected = "Mirror connected"
    }

    private(set) var state: ConnectionState = .notConnected
    private(set) var port: Int = 8765

    /// Fired when the mirror sends a spoken command transcript.
    var onCommandReceived: ((String) -> Void)?

    /// Start the local WebSocket server.
    func startServer(port: Int) {
        self.port = port
        // TODO: stand up a WebSocket server (e.g. Network.framework NWListener)
        // bound to `port`, accept the mirror connection, route inbound frames to
        // onCommandReceived, and update `state`.
        Log.app.info("MirrorBridge.startServer(\(port)) — not yet implemented")
    }

    /// Stop the server and drop any connection.
    func stopServer() {
        // TODO: tear down the listener and connection; set state = .notConnected.
        Log.app.info("MirrorBridge.stopServer — not yet implemented")
    }

    /// Push a response to the connected mirror for display.
    func sendResponse(_ response: AriaResponse) {
        // TODO: encode `response` and send it over the active WebSocket so the
        // mirror can render the orb animation + response text.
        Log.app.debug("MirrorBridge.sendResponse — not yet implemented")
    }
}

/// Mirror settings, persisted in UserDefaults.
struct MirrorSettings {
    var enabled: Bool
    var port: Int

    static func load(_ d: UserDefaults = .standard) -> MirrorSettings {
        MirrorSettings(
            enabled: d.bool(forKey: "mirror.enabled"),
            port: d.object(forKey: "mirror.port") as? Int ?? 8765)
    }
    func save(_ d: UserDefaults = .standard) {
        d.set(enabled, forKey: "mirror.enabled")
        d.set(port, forKey: "mirror.port")
    }
}
