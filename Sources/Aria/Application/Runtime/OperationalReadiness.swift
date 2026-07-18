import CoreGraphics
import Foundation

enum OperationalReadinessTone: Equatable, Sendable {
    case positive
    case neutral
    case attention
}

/// A short, local-only summary shown on Home. It deliberately contains no
/// token, account address, or recorded screen data.
struct OperationalReadinessRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tone: OperationalReadinessTone
}

/// Whether the core Mac capabilities Aria depends on are usable right now. The
/// snapshot does not prompt for permission, capture a screen, or refresh OAuth;
/// it is safe to collect when the Home view becomes visible.
struct OperationalReadiness: Sendable, Equatable {
    let computerUseEnabled: Bool
    let screenRecordingEnabled: Bool
    let microphone: PermissionsManager.Status
    let speech: PermissionsManager.Status
    let linkedAccountCount: Int

    var needsSettings: Bool {
        !computerUseEnabled || microphone != .granted || speech != .granted
    }

    var needsConnectors: Bool { linkedAccountCount == 0 }

    var rows: [OperationalReadinessRow] {
        [computerControlRow, voiceRow, visionRow, accountsRow]
    }

    static func snapshot(store: ConnectorStore = .shared) async -> OperationalReadiness {
        let linkedAccounts = await store.connectors().filter(\.isConnected).count
        return OperationalReadiness(
            computerUseEnabled: AXReader.hasPermission,
            screenRecordingEnabled: CGPreflightScreenCaptureAccess(),
            microphone: PermissionsManager.microphoneStatus,
            speech: PermissionsManager.speechStatus,
            linkedAccountCount: linkedAccounts)
    }

    private var computerControlRow: OperationalReadinessRow {
        computerUseEnabled
            ? OperationalReadinessRow(id: "computer", title: "Computer control", value: "Ready",
                                      detail: "Can see and operate app controls", symbol: "cursorarrow.click.2",
                                      tone: .positive)
            : OperationalReadinessRow(id: "computer", title: "Computer control", value: "Access needed",
                                      detail: "Enable Accessibility in Settings", symbol: "cursorarrow.click.2",
                                      tone: .attention)
    }

    private var voiceRow: OperationalReadinessRow {
        guard microphone == .granted, speech == .granted else {
            let isSetupNeeded = microphone == .undetermined || speech == .undetermined
            let detail: String
            if microphone != .granted, speech != .granted {
                detail = "Enable microphone and speech recognition in Settings"
            } else if microphone != .granted {
                detail = "Enable microphone access in Settings"
            } else {
                detail = "Enable speech recognition in Settings"
            }
            return OperationalReadinessRow(id: "voice", title: "Voice",
                                           value: isSetupNeeded ? "Setup needed" : "Access needed",
                                           detail: detail, symbol: "waveform", tone: .attention)
        }
        return OperationalReadinessRow(id: "voice", title: "Voice", value: "Ready",
                                       detail: "Can listen and understand speech", symbol: "waveform",
                                       tone: .positive)
    }

    private var visionRow: OperationalReadinessRow {
        screenRecordingEnabled
            ? OperationalReadinessRow(id: "vision", title: "Vision", value: "Ready",
                                      detail: "Can inspect the screen when asked", symbol: "eye",
                                      tone: .positive)
            : OperationalReadinessRow(id: "vision", title: "Vision", value: "Optional",
                                      detail: "Enable Screen Recording for visual tools", symbol: "eye",
                                      tone: .neutral)
    }

    private var accountsRow: OperationalReadinessRow {
        guard linkedAccountCount > 0 else {
            return OperationalReadinessRow(id: "accounts", title: "Accounts", value: "No accounts linked",
                                           detail: "Connect apps for email, calendar, and more", symbol: "link",
                                           tone: .neutral)
        }
        let count = linkedAccountCount
        return OperationalReadinessRow(id: "accounts", title: "Accounts",
                                       value: "\(count) linked", detail: "Connected apps are ready when needed",
                                       symbol: "link", tone: .positive)
    }
}
