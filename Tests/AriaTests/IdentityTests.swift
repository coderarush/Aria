import XCTest
@testable import Aria

final class IdentityTests: XCTestCase {

    // MARK: Helpers

    /// A store wired to a throwaway suite + temp file, with personalization on by
    /// default for the test (the opt-in tests flip it off explicitly).
    private func makeStore(enabled: Bool = true) -> (EntityStore, UserDefaults) {
        let suite = "identity-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.set(enabled, forKey: EntityStore.enabledKey)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("identity-\(UUID().uuidString).json")
        return (EntityStore(storeURL: url, defaults: d), d)
    }

    // MARK: Entity lexical resolve (pure)

    func testAliasMatchBeatsNoMatch() {
        let sara = Entity(name: "Sara Lin", kind: .person, notes: "lead designer")
        let bob  = Entity(name: "Bob Stone", kind: .person, notes: "backend engineer")
        let hits = EntityStore.rank("Sara", in: [bob, sara], limit: 5)
        XCTAssertEqual(hits.first?.name, "Sara Lin",
                       "a name reference should resolve the matching person")
    }

    func testReferenceResolvesPersonByName() {
        let sara = Entity(name: "Sara Lin", kind: .person)
        XCTAssertTrue(sara.matches("Sara"))
        XCTAssertGreaterThan(sara.relevance(to: Entity.terms("Sara")), 0)
    }

    func testNameMatchOutranksNotesOnlyMention() {
        let sara  = Entity(name: "Sara Lin", kind: .person, notes: "designer")
        let other = Entity(name: "Project Atlas", kind: .project, notes: "owned by Sara")
        let hits = EntityStore.rank("Sara", in: [other, sara], limit: 5)
        XCTAssertEqual(hits.first?.name, "Sara Lin",
                       "the entity NAMED Sara should outrank one that only mentions her")
    }

    func testAliasResolvesReference() {
        let deck = Entity(name: "Q3 Keynote", kind: .project,
                          aliases: ["the launch deck", "launch deck"],
                          notes: "the big reveal")
        let hits = EntityStore.rank("the launch deck", in: [deck], limit: 5)
        XCTAssertEqual(hits.first?.name, "Q3 Keynote")
        XCTAssertTrue(deck.matches("launch deck"))
    }

    func testNonMatchingReferenceResolvesNothing() {
        let sara = Entity(name: "Sara Lin", kind: .person)
        XCTAssertTrue(EntityStore.rank("quarterly tax filing", in: [sara], limit: 5).isEmpty)
        XCTAssertFalse(sara.matches("quarterly tax filing"))
    }

    func testEmptyReferenceResolvesNothing() {
        let sara = Entity(name: "Sara Lin", kind: .person)
        XCTAssertTrue(EntityStore.rank("", in: [sara], limit: 5).isEmpty)
        XCTAssertTrue(EntityStore.rank("   ", in: [sara], limit: 5).isEmpty)
    }

    // MARK: Upsert / dedupe

    func testUpsertResolvesViaStore() async {
        let (store, _) = makeStore()
        await store.upsert(Entity(name: "Sara Lin", kind: .person, notes: "designer"))
        let resolved = await store.resolve("Sara")
        XCTAssertEqual(resolved?.name, "Sara Lin")
        XCTAssertEqual(resolved?.kind, .person)
    }

    func testUpsertDedupesByName() async {
        let (store, _) = makeStore()
        await store.upsert(Entity(name: "Sara Lin", kind: .person, notes: "designer"))
        await store.upsert(Entity(name: "Sara Lin", kind: .person,
                                  aliases: ["Sar"], notes: "lead designer, west coast"))
        let count = await store.count
        XCTAssertEqual(count, 1, "re-mentioning the same name should merge, not duplicate")
        let resolved = await store.resolve("Sara")
        XCTAssertEqual(resolved?.notes, "lead designer, west coast", "newer notes win")
        XCTAssertEqual(resolved?.aliases, ["Sar"], "aliases union in on upsert")
    }

    func testUpsertUnionsAliases() async {
        let (store, _) = makeStore()
        await store.upsert(Entity(name: "Q3 Keynote", kind: .project, aliases: ["launch deck"]))
        await store.upsert(Entity(name: "Q3 Keynote", kind: .project, aliases: ["the deck"]))
        let resolved = await store.resolve("Q3 Keynote")
        XCTAssertEqual(resolved?.aliases, ["launch deck", "the deck"])
    }

    func testAllReturnsStoredEntities() async {
        let (store, _) = makeStore()
        await store.upsert(Entity(name: "Sara Lin", kind: .person))
        await store.upsert(Entity(name: "Bob Stone", kind: .person))
        let all = await store.all()
        XCTAssertEqual(Set(all.map { $0.name }), ["Sara Lin", "Bob Stone"])
    }

    // MARK: Opt-in gating

    func testDisabledByDefault() async {
        let suite = "identity-default-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!   // no value set → default false
        let store = EntityStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("id-\(UUID().uuidString).json"),
            defaults: d)
        let enabled = await store.isEnabled
        XCTAssertFalse(enabled, "personalization must be opt-in (default off)")
    }

    func testGatedStoreIsNoOp() async {
        let (store, _) = makeStore(enabled: false)
        let stored = await store.upsert(Entity(name: "Sara Lin", kind: .person))
        XCTAssertNil(stored, "upsert is a no-op when personalization is off")
        let resolved = await store.resolve("Sara")
        XCTAssertNil(resolved, "resolve returns nil when personalization is off")
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testWipeOnDisable() async {
        let (store, defaults) = makeStore(enabled: true)
        await store.upsert(Entity(name: "Sara Lin", kind: .person))
        var count = await store.count
        XCTAssertEqual(count, 1)
        // User opts out, then anything that writes triggers the privacy wipe.
        defaults.set(false, forKey: EntityStore.enabledKey)
        _ = await store.upsert(Entity(name: "Bob Stone", kind: .person))
        count = await store.count
        XCTAssertEqual(count, 0, "opting out must wipe the model of the user")
    }

    // MARK: Codable round-trip (persistence shape)

    func testEntityCodableRoundTrip() throws {
        let original = Entity(name: "Sara Lin", kind: .person,
                              aliases: ["Sara", "Sar"], notes: "lead designer")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)
        let back = try decoder.decode(Entity.self, from: data)
        XCTAssertEqual(back.id, original.id)
        XCTAssertEqual(back.name, "Sara Lin")
        XCTAssertEqual(back.kind, .person)
        XCTAssertEqual(back.aliases, ["Sara", "Sar"])
        XCTAssertEqual(back.notes, "lead designer")
    }

    // MARK: Tools

    func testWhoIsResolves() async throws {
        let (store, _) = makeStore()
        await store.upsert(Entity(name: "Sara Lin", kind: .person, notes: "lead designer"))
        let tool = WhoIsTool(store: store)
        let result = try await tool.run(input: ["name": "Sara"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Sara Lin"), result.output)
        XCTAssertTrue(result.output.contains("lead designer"), result.output)
    }

    func testWhoIsUnknownIsGraceful() async throws {
        let (store, _) = makeStore()
        let tool = WhoIsTool(store: store)
        let result = try await tool.run(input: ["name": "Nobody"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("don't have"), result.output)
    }

    func testWhoIsReportsOffWhenDisabled() async throws {
        let (store, _) = makeStore(enabled: false)
        let tool = WhoIsTool(store: store)
        let result = try await tool.run(input: ["name": "Sara"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("off"), result.output)
    }

    func testRememberEntityStores() async throws {
        let (store, _) = makeStore()
        let tool = RememberEntityTool(store: store)
        let result = try await tool.run(input: [
            "name": "Sara Lin", "kind": "person", "notes": "lead designer"
        ])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Sara Lin"), result.output)
        let resolved = await store.resolve("Sara")
        XCTAssertEqual(resolved?.name, "Sara Lin")
    }

    func testRememberEntityReportsOffWhenDisabled() async throws {
        let (store, _) = makeStore(enabled: false)
        let tool = RememberEntityTool(store: store)
        let result = try await tool.run(input: ["name": "Sara Lin", "kind": "person"])
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.lowercased().contains("off"), result.output)
        let resolved = await store.resolve("Sara")
        XCTAssertNil(resolved, "nothing stored while gated")
    }

    func testRememberEntityMissingNameThrows() async {
        let (store, _) = makeStore()
        let tool = RememberEntityTool(store: store)
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput")
        } catch {}
    }

    func testWhoIsMissingNameThrows() async {
        let (store, _) = makeStore()
        let tool = WhoIsTool(store: store)
        do {
            _ = try await tool.run(input: [:])
            XCTFail("expected missingInput")
        } catch {}
    }

    // MARK: StyleProfile.analyze (pure)

    func testAnalyzeEmptyIsNeutral() {
        XCTAssertEqual(StyleProfile.analyze([]), StyleProfile.neutral)
        XCTAssertEqual(StyleProfile.analyze(["", "   "]), StyleProfile.neutral)
        XCTAssertEqual(StyleProfile.neutral.styleGuide(), "")
    }

    func testCasualVsFormalProduceDifferentProfiles() {
        let casual = StyleProfile.analyze([
            "hey! got it 😄 i'll ping you later",
            "yeah that's fine, don't worry about it",
            "lol sounds good, ttyl"
        ])
        let formal = StyleProfile.analyze([
            "Dear Sara, I am writing to confirm that the proposal has been reviewed and approved by the committee. Please let me know if you require any further information. Best regards, Arush.",
            "Hello team, I would like to schedule a meeting to discuss the quarterly results in detail and align on our strategy for the coming period. Sincerely, Arush."
        ])
        XCTAssertGreaterThan(formal.formality, casual.formality,
                             "formal samples should score more formal than casual ones")
        XCTAssertGreaterThan(formal.avgSentenceLength, casual.avgSentenceLength)
        XCTAssertGreaterThan(casual.emojiPer100Words, 0, "casual samples used emoji")
        XCTAssertEqual(formal.emojiPer100Words, 0, "formal samples used no emoji")
        XCTAssertGreaterThan(casual.contractionRate, formal.contractionRate)
    }

    func testStyleGuidesDifferForCasualVsFormal() {
        let casual = StyleProfile.analyze([
            "hey! got it 😄 i'll ping you later",
            "yeah that's fine, don't worry about it",
            "lol sounds good 🙌"
        ]).styleGuide()
        let formal = StyleProfile.analyze([
            "Dear Sara, I am writing to confirm that the proposal has been reviewed and approved by the committee. Please advise if further detail is required. Best regards.",
            "Hello team, I would like to schedule a meeting to discuss the quarterly results and align on strategy. Sincerely."
        ]).styleGuide()

        XCTAssertNotEqual(casual, formal)
        XCTAssertTrue(casual.lowercased().contains("casual"), casual)
        XCTAssertTrue(casual.lowercased().contains("emoji are welcome"), casual)
        XCTAssertTrue(formal.lowercased().contains("formal"), formal)
        XCTAssertTrue(formal.lowercased().contains("no emoji"), formal)
    }

    func testStyleGuideWordingForTerseCasualNoSignOff() {
        // A terse, casual writer who never signs off or uses emoji.
        let p = StyleProfile.analyze([
            "got it",
            "on it now",
            "yep works for me",
            "done"
        ])
        let guide = p.styleGuide().lowercased()
        XCTAssertTrue(guide.contains("short") || guide.contains("brief"), guide)
        XCTAssertTrue(guide.contains("no sign-off"), guide)
        XCTAssertTrue(guide.contains("no emoji"), guide)
        XCTAssertTrue(guide.contains("no greeting") || guide.contains("skip the greeting"), guide)
    }

    func testAnalyzeIsDeterministic() {
        let samples = ["hey there, what's up?", "all good — talk soon"]
        XCTAssertEqual(StyleProfile.analyze(samples), StyleProfile.analyze(samples))
    }

    func testStyleProfileCodableRoundTrip() throws {
        let p = StyleProfile.analyze(["Hi Sara, thanks for the update. Best, Arush."])
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(StyleProfile.self, from: data)
        XCTAssertEqual(back, p)
    }
}
