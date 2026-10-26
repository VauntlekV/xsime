import XCTest
import UIKit
import RimesCore
@testable import RIMES

@MainActor final class BufferImportTests: XCTestCase {
    func testOpeningTheBufferNeverShowsOrImportsHostTextAndTheFieldIsLeftAlone() throws {
        for width: CGFloat in [320, 393, 852] {
            let (window, controller) = host(width: width); defer { window.isHidden = true }
            let text = String(repeating: "输入框已有的长文字，", count: 12)
            setHost(text, controller: controller)
            controller.developmentBuffer(""); window.layoutIfNeeded()
            XCTAssertNil(controller.layoutViews.buffer.subviews.first { $0.accessibilityIdentifier == "keyboard.buffer.paste" }, "The Buffer input has no paste control")
            // No hint text and no tap-to-import row: the field's text is only moved in by the pinch gesture.
            XCTAssertNil(controller.layoutViews.buffer.subviews.first { $0.accessibilityIdentifier == "keyboard.buffer.importHost" })
            XCTAssertNil(controller.layoutViews.source.onTapBackground)
            XCTAssertEqual(controller.developmentBufferSource.text, "")
            XCTAssertEqual(controller.layoutProxy.native.text, text)
            let height = controller.view.bounds.height
            controller.developmentChoose(.english); controller.developmentType("x"); window.layoutIfNeeded()
            XCTAssertEqual(controller.layoutProxy.native.text, text)
            XCTAssertEqual(controller.view.bounds.height, height)
        }
    }

    func testImportMovesFullTextFromBeginningMiddleAndEndIncludingEmojiAndNewlines() async throws {
        let text = "前👨‍👩‍👧‍👦e\u{301}\n后。"
        for cursor in [0, 1, text.utf16.count] {
            let (window, controller) = host(); defer { window.isHidden = true }
            setHost(text, cursor: cursor, controller: controller)
            controller.developmentBuffer("")
            controller.developmentImportHostText()
            await controller.developmentWaitForBufferImport()
            XCTAssertEqual(controller.developmentBufferSource.text, text)
            XCTAssertEqual(controller.layoutProxy.native.text, "")
            XCTAssertEqual(controller.layoutProxy.native.selectedRange, NSRange(location: 0, length: 0))
            XCTAssertTrue(controller.developmentTypingSession.isEmpty, "Imports are not typing metrics")
        }
    }

    func testStalePreviewCannotDeleteOrImportAnEditedOrDifferentField() async throws {
        for changesIdentity in [false, true] {
            let (window, controller) = host(); defer { window.isHidden = true }
            setHost("原文", controller: controller); controller.developmentBuffer("")
            setHost("新的输入框文字", controller: controller)
            if changesIdentity { controller.layoutProxy.documentIdentifier = UUID() }
            controller.developmentImportHostText()
            await controller.developmentWaitForBufferImport()
            XCTAssertEqual(controller.layoutProxy.native.text, "新的输入框文字")
            XCTAssertEqual(controller.developmentBufferSource.text, "")
        }
    }

    func testTruncatedContextCopiesOnlyWhatWasPreviewedAndRestoresCaretWithoutDeletion() async throws {
        for cursor in [0, 5, 10] {
            let (window, controller) = host(); defer { window.isHidden = true }
            let text = "一二三四五六七八九十"
            setHost(text, cursor: cursor, controller: controller); controller.layoutProxy.contextLimit = 3
            let expected = (controller.layoutProxy.documentContextBeforeInput ?? "") + (controller.layoutProxy.documentContextAfterInput ?? "")
            controller.developmentBuffer("")
            controller.developmentImportHostText()
            await controller.developmentWaitForBufferImport()
            XCTAssertEqual(controller.developmentBufferSource.text, expected)
            XCTAssertEqual(controller.layoutProxy.native.text, text)
            XCTAssertEqual(controller.layoutProxy.native.selectedRange.location, cursor)
            XCTAssertTrue(controller.developmentStatus.contains(L("原文保留", "original stays")))
        }
    }

    func testPossiblyTruncatedSelectionIsNeverDeleted() async throws {
        let (window, controller) = host(); defer { window.isHidden = true }
        setHost("前一二三四五后", controller: controller)
        controller.layoutProxy.native.selectedRange = NSRange(location: 1, length: 5)
        controller.layoutProxy.contextLimit = 2
        controller.developmentBuffer("")
        controller.developmentImportHostText()
        await controller.developmentWaitForBufferImport()
        XCTAssertEqual(controller.developmentBufferSource.text, "一二")
        XCTAssertEqual(controller.layoutProxy.native.text, "前一二三四五后")
        XCTAssertEqual(controller.layoutProxy.native.selectedRange, NSRange(location: 1, length: 5))
    }

    func testDelayedAndIgnoredHostDeletionNeverLosesTheSavedSource() async throws {
        for ignored in [false, true] {
            let (window, controller) = host(); defer { window.isHidden = true }
            setHost("甲乙😀", controller: controller)
            controller.layoutProxy.ignoresDeletion = ignored
            controller.layoutProxy.deletionDelay = 0.03
            controller.developmentBuffer("")
            controller.developmentImportHostText()
            await controller.developmentWaitForBufferImport()
            XCTAssertEqual(controller.developmentBufferSource.text, "甲乙😀")
            XCTAssertEqual(controller.layoutProxy.native.text, ignored ? "甲乙😀" : "")
        }
    }

    func testFieldChangeDuringDeletionStopsBeforeTouchingTheNewField() async throws {
        let (window, controller) = host(); defer { window.isHidden = true }
        setHost("甲乙丙", controller: controller); controller.developmentBuffer("")
        controller.layoutProxy.onProxyWrite = {
            controller.textDidChange(nil); controller.selectionDidChange(nil)
            guard controller.layoutProxy.native.text.count < 3 else { return }
            controller.layoutProxy.onProxyWrite = nil
            controller.layoutProxy.documentIdentifier = UUID()
            self.setHost("新目标", controller: controller); controller.textDidChange(nil)
        }
        controller.developmentImportHostText()
        await controller.developmentWaitForBufferImport()
        XCTAssertEqual(controller.layoutProxy.native.text, "新目标")
        XCTAssertEqual(controller.developmentBufferSource.text, "甲乙丙")
    }

    func testHostTextIsOfferedToThePinchOnlyWhileTheBufferIsEmptyAndTheFieldHasText() throws {
        let (window, controller) = host(); defer { window.isHidden = true }
        controller.developmentBuffer(""); XCTAssertFalse(controller.developmentOffersHostText)
        setHost("新文字", controller: controller); controller.textDidChange(nil)
        XCTAssertTrue(controller.developmentOffersHostText)
        setHost("", controller: controller); controller.textDidChange(nil)
        XCTAssertFalse(controller.developmentOffersHostText)
    }

    func testOptimisticStaleProxyCannotAuthorizeDeletingRealHostText() async throws {
        let (window, controller) = host(); defer { window.isHidden = true }
        setHost("Buffer import 46", controller: controller)
        let cached = UITextView(); cached.text = "Buffe"; cached.selectedRange = NSRange(location: 5, length: 0)
        controller.layoutProxy.optimisticContext = cached
        controller.layoutProxy.cursorDelay = 0.04
        controller.developmentBuffer("")
        controller.developmentImportHostText()
        await controller.developmentWaitForBufferImport()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.layoutProxy.native.text, "Buffer import 46")
        XCTAssertEqual(controller.developmentBufferSource.text, "")
    }

    func testUnacknowledgedCursorPredictionCannotAuthorizeDeletion() async throws {
        let (window, controller) = host(); defer { window.isHidden = true }
        setHost("需要确认", controller: controller)
        controller.layoutProxy.acknowledgesCursor = false
        controller.developmentBuffer("")
        controller.developmentImportHostText()
        await controller.developmentWaitForBufferImport()
        XCTAssertEqual(controller.layoutProxy.native.text, "需要确认")
        XCTAssertEqual(controller.developmentBufferSource.text, "")
    }


    private func setHost(_ text: String, cursor: Int? = nil, controller: KeyboardViewController) {
        controller.layoutProxy.native.text = text
        controller.layoutProxy.native.selectedRange = NSRange(location: cursor ?? text.utf16.count, length: 0)
    }
    private func host(width: CGFloat = 393) -> (UIWindow, KeyboardViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
        let parent = UIViewController(); window.rootViewController = parent; window.makeKeyAndVisible()
        let controller = KeyboardViewController(); controller.layoutNeedsInputModeSwitchKey = false
        controller.loadViewIfNeeded(); controller.developmentResetPreferences()
        parent.addChild(controller); parent.view.addSubview(controller.view); controller.didMove(toParent: parent)
        NSLayoutConstraint.activate([controller.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor), controller.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor), controller.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)])
        controller.viewWillAppear(false); controller.developmentChoose(.english); controller.developmentBuffer(nil)
        controller.layoutProxy.onProxyWrite = { [weak controller] in controller?.textDidChange(nil); controller?.selectionDidChange(nil) }
        window.layoutIfNeeded()
        return (window, controller)
    }
}
