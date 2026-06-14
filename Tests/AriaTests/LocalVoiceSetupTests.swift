import XCTest
@testable import Aria

/// V11 — onboarding "fast local voice" one-tap: pure recommendation/label
/// logic for the fast instruct chat model the voice path uses, plus the
/// persistence contract (`app.localChatModel`) that LocalFirstRouter reads.
@MainActor
final class LocalVoiceSetupTests: XCTestCase {

    // MARK: fast voice-model recommendation by RAM tier

    func testConstrainedRAMGetsSmallestFastModel() {
        XCTAssertEqual(LocalVoiceSetupView.recommendedVoiceModel(ramGB: 8), "llama3.2:1b")
        XCTAssertEqual(LocalVoiceSetupView.recommendedVoiceModel(ramGB: 15), "llama3.2:1b")
    }

    func testTypicalAndHighRAMGetFast3B() {
        XCTAssertEqual(LocalVoiceSetupView.recommendedVoiceModel(ramGB: 16), "llama3.2:3b")
        XCTAssertEqual(LocalVoiceSetupView.recommendedVoiceModel(ramGB: 24), "llama3.2:3b")
        XCTAssertEqual(LocalVoiceSetupView.recommendedVoiceModel(ramGB: 64), "llama3.2:3b")
    }

    func testHighTierMatchesShippedDefault() {
        // 16GB+ recommendation must equal the router's shipped default so the
        // out-of-box voice model is consistent with LocalFirstRouter.
        XCTAssertEqual(LocalVoiceSetupView.recommendedVoiceModel(ramGB: 16),
                       LocalVoiceSetupView.defaultChatModel)
    }

    func testRecommendationIsAlwaysAFastInstructModel() {
        for ram in [4, 8, 16, 24, 32, 96, 192] {
            let m = LocalVoiceSetupView.recommendedVoiceModel(ramGB: ram)
            XCTAssertTrue(m.hasPrefix("llama3.2:"),
                          "voice model \(m) for \(ram)GB should be a fast instruct model")
        }
    }

    // MARK: display names

    func testChatDisplayNamesAndFallback() {
        XCTAssertEqual(LocalVoiceSetupView.chatDisplayName("llama3.2:1b"), "Llama 3.2 1B")
        XCTAssertEqual(LocalVoiceSetupView.chatDisplayName("llama3.2:3b"), "Llama 3.2 3B")
        XCTAssertEqual(LocalVoiceSetupView.chatDisplayName("llama3.1:8b"), "Llama 3.1 8B")
        // Unknown tags fall back to the raw tag — never empty.
        XCTAssertEqual(LocalVoiceSetupView.chatDisplayName("mystery:7b"), "mystery:7b")
    }

    // MARK: status → label

    func testStatusLabelsAreNonEmptyForEveryPhase() {
        let phases: [LocalVoiceSetupView.Phase] =
            [.idle, .checking, .downloading, .ready, .failed, .skipped, .ollamaMissing]
        for p in phases {
            XCTAssertFalse(LocalVoiceSetupView.statusLabel(for: p).isEmpty,
                           "phase \(p) must have a label")
        }
    }

    func testStatusLabelsDistinguishKeyStates() {
        XCTAssertNotEqual(LocalVoiceSetupView.statusLabel(for: .ready),
                          LocalVoiceSetupView.statusLabel(for: .skipped))
        XCTAssertNotEqual(LocalVoiceSetupView.statusLabel(for: .downloading),
                          LocalVoiceSetupView.statusLabel(for: .failed))
    }

    // MARK: persistence contract (key LocalFirstRouter reads)

    func testPersistKeyMatchesRouterChatModelKey() {
        // The onboarding view persists under the same key the router reads.
        XCTAssertEqual(LocalVoiceSetupView.chatModelKey, "app.localChatModel")
    }

    func testPersistedModelRoundTripsThroughUserDefaults() {
        let key = LocalVoiceSetupView.chatModelKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let model = LocalVoiceSetupView.recommendedVoiceModel(ramGB: 16)
        UserDefaults.standard.set(model, forKey: key)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "llama3.2:3b")
    }
}
