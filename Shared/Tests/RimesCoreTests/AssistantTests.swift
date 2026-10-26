import XCTest
@testable import RimesCore

final class AssistantTests: XCTestCase {
    func testDefaultBarIsEveryBuiltInPluginInOrder() {
        XCTAssertEqual(AssistantLibrary().entranceEntries, ["apple.translation", "ai.ask", "ai.polish", "ai.poem", "ai.art"])
    }
    func testNewPresetStaysOffTheBarUntilAdded() throws {
        var library = AssistantLibrary()
        let preset = AssistantPreset(name: "哄睡", instruction: "温柔地哄对方入睡")
        XCTAssertTrue(library.save(preset))
        XCTAssertFalse(library.entranceEntries.contains(preset.entryID))
        library.setOnEntrance(preset.entryID, true)
        XCTAssertEqual(library.entranceEntries.last, preset.entryID)
        XCTAssertEqual(library.preset(entry: preset.entryID)?.name, "哄睡")
    }
    func testUserChoosesWhichEntriesAppearAndTheirOrder() {
        var library = AssistantLibrary()
        library.setOnEntrance("ai.polish", false); library.setOnEntrance("ai.art", false)
        XCTAssertEqual(library.entranceEntries, ["apple.translation", "ai.ask", "ai.poem"])
        library.moveEntrance(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(library.entranceEntries, ["ai.poem", "apple.translation", "ai.ask"])
    }
    func testRemovingAPresetTakesItOffTheBarAndUnknownEntriesAreIgnored() {
        var library = AssistantLibrary(entrance: ["preset.\(UUID().uuidString)", "nonsense", "ai.ask"])
        let preset = AssistantPreset(name: "A", instruction: "B")
        library.save(preset); library.setOnEntrance(preset.entryID, true)
        XCTAssertEqual(library.entranceEntries, ["ai.ask", preset.entryID])
        library.remove(preset.id)
        XCTAssertEqual(library.entranceEntries, ["ai.ask"])
    }
    func testInvalidPresetsAreRejected() {
        var library = AssistantLibrary()
        XCTAssertFalse(library.save(AssistantPreset(name: " ", instruction: "x")))
        XCTAssertFalse(library.save(AssistantPreset(name: "n", instruction: "")))
        XCTAssertFalse(library.save(AssistantPreset(name: "n", instruction: String(repeating: "字", count: 2000))))
        XCTAssertTrue(library.presets.isEmpty)
    }
    func testStartersAreValidInBothLanguagesAndDecodeRoundTrips() throws {
        for starter in AssistantLibrary.starters {
            XCTAssertTrue(starter.preset(chinese: true).isValid); XCTAssertTrue(starter.preset(chinese: false).isValid)
        }
        var library = AssistantLibrary(); library.save(AssistantLibrary.starters[0].preset(chinese: true)); library.entrance = ["ai.ask"]
        XCTAssertEqual(try JSONDecoder().decode(AssistantLibrary.self, from: JSONEncoder().encode(library)), library)
    }
}
