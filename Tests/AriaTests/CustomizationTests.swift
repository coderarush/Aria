import XCTest
@testable import Aria

final class SoundThemeTests: XCTestCase {

    func testThemesProduceDistinctVoicings() {
        let aurora = UISounds.pcm(for: .wake, theme: .aurora)
        let crystal = UISounds.pcm(for: .wake, theme: .crystal)
        let calm = UISounds.pcm(for: .wake, theme: .calm)
        XCTAssertFalse(aurora.isEmpty)
        XCTAssertNotEqual(aurora, crystal)
        XCTAssertNotEqual(aurora, calm)
        XCTAssertNotEqual(crystal, calm)
        // Same gesture length: theme changes voicing, not the sound's shape.
        XCTAssertEqual(aurora.count, crystal.count)
        XCTAssertEqual(aurora.count, calm.count)
    }

    func testAllKindsRenderInAllThemes() {
        for kind in UISounds.Kind.allCases {
            for theme in SoundTheme.allCases {
                let pcm = UISounds.pcm(for: kind, theme: theme)
                XCTAssertFalse(pcm.isEmpty, "\(kind)/\(theme) rendered empty")
                // Nothing clips.
                XCTAssertNil(pcm.first { $0 == Int16.max || $0 == Int16.min })
            }
        }
    }

    func testDefaultThemeIsAurora() {
        UserDefaults.standard.removeObject(forKey: SoundTheme.key)
        XCTAssertEqual(SoundTheme.current, .aurora)
        XCTAssertEqual(UISounds.pcm(for: .done), UISounds.pcm(for: .done, theme: .aurora))
    }
}

final class LocalVoiceTests: XCTestCase {

    private func candidate(_ name: String, _ lang: String, _ quality: Int) -> LocalVoice.Candidate {
        LocalVoice.Candidate(id: name.lowercased(), language: lang, quality: quality, name: name)
    }

    func testPersonalBeatsPremiumBeatsEnhancedBeatsDefault() {
        let best = LocalVoice.best([
            candidate("Samantha", "en-US", 0),
            candidate("Ava", "en-US", 2),
            candidate("Evan", "en-US", 1),
            candidate("Me", "en-US", 3),
        ])
        XCTAssertEqual(best?.name, "Me")
    }

    func testEnUSPreferredWithinSameQuality() {
        let best = LocalVoice.best([
            candidate("Karen", "en-AU", 2),
            candidate("Ava", "en-US", 2),
        ])
        XCTAssertEqual(best?.name, "Ava")
    }

    func testNonEnglishFilteredOutAndEmptySafe() {
        XCTAssertNil(LocalVoice.best([candidate("Yuna", "ko-KR", 2)]))
        XCTAssertNil(LocalVoice.best([]))
    }
}

final class CustomInstructionsTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CustomInstructions.key)
        super.tearDown()
    }

    func testEmptyAndWhitespaceYieldNoSuffix() {
        UserDefaults.standard.removeObject(forKey: CustomInstructions.key)
        XCTAssertEqual(CustomInstructions.promptSuffix, "")
        UserDefaults.standard.set("   \n ", forKey: CustomInstructions.key)
        XCTAssertEqual(CustomInstructions.promptSuffix, "")
    }

    func testInstructionsAppearInSuffix() {
        UserDefaults.standard.set("Call me Cap. Metric units only.", forKey: CustomInstructions.key)
        XCTAssertTrue(CustomInstructions.promptSuffix.contains("Call me Cap. Metric units only."))
        XCTAssertTrue(CustomInstructions.promptSuffix.contains("standing instructions"))
    }

    func testOverlongInstructionsAreCapped() {
        UserDefaults.standard.set(String(repeating: "x", count: 5000), forKey: CustomInstructions.key)
        XCTAssertEqual(CustomInstructions.current.count, CustomInstructions.maxLength)
    }
}
