import SwiftUI
import AppKit

/// Accent-color theming. The only customizable color in Aria; everything else is
/// neutral system material.
enum AccentChoice: Equatable {
    case system
    case preset(String)
    case custom(hex: String)
}

enum Theme {
    /// Curated calm presets (id, display name, color).
    static let presets: [(id: String, name: String, color: Color)] = [
        ("graphite", "Graphite", Color(red: 0.55, green: 0.58, blue: 0.62)),
        ("blue",     "Blue",     Color(red: 0.23, green: 0.51, blue: 0.96)),
        ("teal",     "Teal",     Color(red: 0.10, green: 0.70, blue: 0.67)),
        ("violet",   "Violet",   Color(red: 0.55, green: 0.40, blue: 0.95)),
        ("amber",    "Amber",    Color(red: 0.96, green: 0.70, blue: 0.20)),
        ("rose",     "Rose",     Color(red: 0.95, green: 0.40, blue: 0.55)),
        ("green",    "Green",    Color(red: 0.25, green: 0.78, blue: 0.45)),
    ]

    static func presetColor(id: String) -> Color? {
        presets.first { $0.id == id }?.color
    }

    /// Resolve the live accent color for a choice.
    static func color(for choice: AccentChoice) -> Color {
        switch choice {
        case .system: return Color(nsColor: .controlAccentColor)
        case .preset(let id): return presetColor(id: id) ?? Color(nsColor: .controlAccentColor)
        case .custom(let hex): return color(fromHex: hex) ?? Color(nsColor: .controlAccentColor)
        }
    }

    /// Parse "#RRGGBB" or "RRGGBB" → Color; nil if invalid.
    static func color(fromHex raw: String) -> Color? {
        let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    static func encode(_ choice: AccentChoice) -> String {
        switch choice {
        case .system: return "system"
        case .preset(let id): return "preset:\(id)"
        case .custom(let hex): return "custom:\(hex)"
        }
    }

    static func decodeChoice(_ raw: String) -> AccentChoice {
        if raw == "system" { return .system }
        if raw.hasPrefix("preset:") { return .preset(String(raw.dropFirst(7))) }
        if raw.hasPrefix("custom:") { return .custom(hex: String(raw.dropFirst(7))) }
        return .system
    }
}
