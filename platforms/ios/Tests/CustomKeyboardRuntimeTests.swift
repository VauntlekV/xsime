import XCTest
import UIKit
import RimesCore
@testable import RIMES

@MainActor final class CustomKeyboardRuntimeTests: XCTestCase {
    func testCustomCharacterAndFunctionFramesUseSharedGeometry() throws {
        for width: CGFloat in [320, 393, 852] {
            let (window, controller) = host(width: width)
            defer { window.isHidden = true }
            for template in CustomKeyboardLayout.templates {
                var layout = template
                // Exercise reordered characters, unequal widths and a function in a letter row.
                layout.rows[0].swapAt(0, 4)
                layout.rows[1][0].width = 1.5
                let shift = layout.rows[3].remove(at: 1)
                layout.rows[2].insert(shift, at: 0)
                controller.developmentSetCustomLayout(layout)
                window.layoutIfNeeded(); controller.view.layoutIfNeeded()
                let surface = controller.layoutViews.keys
                XCTAssertTrue(surface.usesCustomLayout)
                let geometry = layout.geometry(width: Double(surface.bounds.width), landscape: width > 590)
                XCTAssertEqual(surface.bounds.height, geometry.height, accuracy: 0.5)
                for item in geometry.frames {
                    let actual: CGRect
                    if item.key.action == .character {
                        actual = try XCTUnwrap(surface.developmentKeyFrames[item.key.text])
                        XCTAssertEqual(surface.developmentOrdinaryKey(at: CGPoint(x: item.x + item.width / 2, y: item.y + item.height / 2)), item.key.text)
                    } else {
                        let button = try XCTUnwrap(surface.customFunctionViews[item.key.action])
                        XCTAssertTrue(button.superview === surface)
                        XCTAssertFalse(button.isHidden)
                        actual = button.frame
                    }
                    assertFrame(actual, equals: CGRect(x: item.x, y: item.y, width: item.width, height: item.height))
                }
                XCTAssertTrue(controller.layoutViews.bottom.isHidden)
            }
        }
    }

    func testCustomLayoutCannotChangeChordOrItsEnglishShiftEmojiAndNumberModes() {
        for chordLayout in ChordLayout.allCases {
            let (window, controller) = host()
            defer { window.isHidden = true }
            controller.developmentChoose(.chord); controller.developmentSetLayout(chordLayout)
            window.layoutIfNeeded()
            let original = snapshot(controller)
            controller.developmentChoose(.pinyin)
            controller.developmentSetCustomLayout(CustomKeyboardLayout.templates[2])
            window.layoutIfNeeded()
            XCTAssertTrue(controller.layoutViews.keys.usesCustomLayout)
            controller.developmentChoose(.chord); window.layoutIfNeeded()
            XCTAssertEqual(snapshot(controller), original)

            let modes: [(String, (KeyboardViewController) -> Void)] = [
                ("normal", { _ in }), ("English", { $0.developmentLanguage() }),
                ("Shift", { $0.developmentShift() }), ("emoji", { $0.layoutViews.keys.showEmoji() }),
                ("numbers", { $0.developmentNumeric() })
            ]
            for (name, selectMode) in modes {
                controller.developmentResetPreferences(); controller.developmentChoose(.chord)
                controller.developmentSetLayout(chordLayout)
                controller.developmentSetCustomLayout(nil)
                selectMode(controller); window.layoutIfNeeded()
                let baseline = snapshot(controller)
                controller.developmentSetCustomLayout(CustomKeyboardLayout.templates[0])
                window.layoutIfNeeded()
                XCTAssertFalse(controller.layoutViews.keys.usesCustomLayout, name)
                XCTAssertEqual(snapshot(controller), baseline, name)
            }
        }
    }

    func testFunctionKeysPreserveNativePlacementAndBindingsAfterModeSwitchAndRestore() throws {
        let (window, controller) = host(needsGlobe: true)
        defer { window.isHidden = true }
        let bottom = controller.layoutViews.bottom
        let originalSubviews = bottom.arrangedSubviews
        let originalIdentifiers = originalSubviews.map { ObjectIdentifier($0) }
        let originalFrames = originalSubviews.map(\.frame)
        let originalHidden = originalSubviews.map(\.isHidden)
        let space = controller.developmentSpaceKey, delete = controller.developmentDelete
        controller.developmentSetCustomLayout(CustomKeyboardLayout.templates[1])
        window.layoutIfNeeded()
        XCTAssertTrue(space.superview === controller.layoutViews.keys)
        XCTAssertTrue(delete.superview === controller.layoutViews.keys)
        XCTAssertFalse(controller.layoutViews.globe.isHidden)
        XCTAssertTrue(controller.layoutViews.globe.superview === bottom)
        XCTAssertFalse(bottom.isHidden)
        XCTAssertGreaterThan(controller.layoutViews.globe.bounds.width, 0)

        controller.developmentNumeric(); window.layoutIfNeeded()
        XCTAssertFalse(controller.layoutViews.keys.usesCustomLayout)
        XCTAssertEqual(bottom.arrangedSubviews.map { ObjectIdentifier($0) }, originalIdentifiers)
        XCTAssertTrue(controller.layoutViews.keys.usesStandardLayout)
        XCTAssertTrue(space.superview === controller.layoutViews.keys); XCTAssertTrue(delete.superview === controller.layoutViews.keys)
        controller.developmentNumeric(); window.layoutIfNeeded()
        XCTAssertTrue(controller.layoutViews.keys.usesCustomLayout)
        controller.developmentSetCustomLayout(nil); window.layoutIfNeeded()
        XCTAssertEqual(bottom.arrangedSubviews.map { ObjectIdentifier($0) }, originalIdentifiers)
        XCTAssertEqual(bottom.arrangedSubviews.map(\.isHidden), originalHidden)
        for (view, frame) in zip(bottom.arrangedSubviews, originalFrames) {
            if !view.isHidden { assertFrame(view.frame, equals: frame) }
            XCTAssertFalse(view.translatesAutoresizingMaskIntoConstraints)
        }
        XCTAssertNotNil(delete.onDelete)
        XCTAssertEqual(controller.developmentSpaceKey, space)
    }

    func testMovedFunctionButtonsStillTypeDeleteMoveCursorAndReturnFromNumbers() throws {
        let (window, controller) = host()
        defer { window.isHidden = true }
        controller.developmentChoose(.english)
        var layout = CustomKeyboardLayout.templates[0]
        let functions = layout.rows.removeLast()
        layout.rows.insert(Array(functions.reversed()), at: 0)
        controller.developmentSetCustomLayout(layout); window.layoutIfNeeded()
        let surface = controller.layoutViews.keys
        func key(_ action: CustomKeyAction) throws -> UIButton {
            try XCTUnwrap(surface.customFunctionViews[action] as? UIButton)
        }
        func type(_ letter: String) throws {
            let element = try XCTUnwrap(surface.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }
                .first { $0.accessibilityLabel == letter.uppercased() })
            XCTAssertTrue(element.accessibilityActivate())
        }
        try type("a"); try type("b")
        try key(.space).sendActions(for: .touchUpInside)
        try type("c")
        XCTAssertEqual(controller.layoutProxy.native.text, "ab c")
        XCTAssertTrue(try key(.backspace).accessibilityActivate())
        XCTAssertEqual(controller.layoutProxy.native.text, "ab ")
        try key(.enter).sendActions(for: .touchUpInside)
        XCTAssertEqual(controller.layoutProxy.native.text, "ab \n")

        let space = controller.developmentSpaceKey
        let m = space.machine
        m.down(1, at: CGPoint(x: m.width / 2, y: 20)); m.holdElapsed(1)
        m.move(1, to: CGPoint(x: m.width / 2 - SplitSpaceMachine.caretStep, y: 20))
        XCTAssertEqual(controller.layoutProxy.native.selectedRange.location, 3)
        m.up(1)

        let numbers = try key(.numbers)
        numbers.sendActions(for: .touchUpInside); window.layoutIfNeeded()
        XCTAssertTrue(surface.numeric); XCTAssertFalse(surface.usesCustomLayout)
        XCTAssertTrue(numbers.superview === controller.layoutViews.keys)
        XCTAssertEqual(controller.layoutViews.keys.standardMode, .numeric)
        numbers.sendActions(for: .touchUpInside); window.layoutIfNeeded()
        XCTAssertFalse(surface.numeric); XCTAssertTrue(surface.usesCustomLayout)
        XCTAssertTrue(numbers.superview === surface)
        try key(.shift).sendActions(for: .touchUpInside)
        try type("d")
        XCTAssertEqual(controller.layoutProxy.native.text, "ab D\n")
    }

    private struct LayoutSnapshot: Equatable {
        var keyFrames: [String: CGRect]
        var keyArea: CGRect
        var bottomArea: CGRect
        var visibleFunctions: [String]
        var functionFrames: [CGRect]
        var controllerHeight: CGFloat
        var resolvesChords: Bool
        var shifted: Bool
        var english: Bool
        var numeric: Bool
        var emoji: Bool
    }

    private func snapshot(_ controller: KeyboardViewController) -> LayoutSnapshot {
        let views = controller.layoutViews
        let functions = views.bottom.arrangedSubviews.filter { !$0.isHidden }
        return .init(keyFrames: views.keys.developmentKeyFrames, keyArea: views.keys.frame,
                     bottomArea: views.bottom.frame, visibleFunctions: functions.map { $0.accessibilityIdentifier ?? "" },
                     functionFrames: functions.map(\.frame), controllerHeight: controller.view.bounds.height,
                     resolvesChords: views.keys.resolvesChords, shifted: views.keys.shifted,
                     english: views.keys.englishInput, numeric: views.keys.numeric, emoji: views.keys.emojiMode)
    }

    private func assertFrame(_ actual: CGRect, equals expected: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.01, file: file, line: line)
    }

    private func host(width: CGFloat = 393, needsGlobe: Bool = false) -> (UIWindow, KeyboardViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
        let parent = UIViewController(); window.rootViewController = parent; window.makeKeyAndVisible()
        let controller = KeyboardViewController(); controller.layoutNeedsInputModeSwitchKey = needsGlobe
        parent.addChild(controller); parent.view.addSubview(controller.view); controller.didMove(toParent: parent)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
        controller.developmentResetPreferences(); controller.developmentSetCustomLayout(nil)
        controller.developmentContent(); controller.developmentBuffer(nil); window.layoutIfNeeded()
        return (window, controller)
    }
}

final class CustomLayoutStoreTests: XCTestCase {
    func testDraftIsSeparateFromActiveSnapshotAndExistingConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = root.appendingPathComponent("configuration-v1.json")
        let previousConfiguration = Data("{\"chordLayout\":\"orthogonal\",\"customUserSetting\":42}".utf8)
        try previousConfiguration.write(to: configuration)
        let store = RIMES.CustomLayoutStore(root: root)
        let active = CustomKeyboardLayout.templates[1]
        try store.apply(active)
        let revision = store.load().revision
        var draft = active; draft.name = "正在调整"; draft.rows[0][0].text = ""
        try store.saveDraft(draft)
        let library = store.load()
        XCTAssertEqual(library.layouts.first, draft)
        XCTAssertEqual(library.active, active)
        XCTAssertEqual(library.revision, revision)
        XCTAssertThrowsError(try store.apply(draft))
        XCTAssertEqual(store.load().active, active)
        XCTAssertEqual(store.load().revision, revision)
        XCTAssertEqual(try Data(contentsOf: configuration), previousConfiguration)
        try store.apply(nil)
        XCTAssertNil(store.load().active)
        XCTAssertNotEqual(store.load().revision, revision)
        XCTAssertEqual(store.load().layouts.first, draft)
        XCTAssertEqual(try Data(contentsOf: configuration), previousConfiguration)
    }

    func testInvalidStoredActiveFallsBackWithoutDiscardingEditableDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var draft = CustomKeyboardLayout.templates[0]
        draft.rows[3].removeAll { $0.action == .language }
        let library = RIMES.CustomLayoutLibrary(layouts: [draft], active: draft, revision: "invalid-import")
        try JSONEncoder().encode(library).write(to: root.appendingPathComponent("keyboard-layouts-v1.json"))
        let loaded = RIMES.CustomLayoutStore(root: root).load()
        XCTAssertNil(loaded.active)
        XCTAssertEqual(loaded.layouts, [draft])
    }
}
