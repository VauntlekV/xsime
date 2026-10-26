import AppKit
import Foundation

/// In-process AppKit rendering and NSTextInputClient protocol checks. No input
/// source is selected, no real key events are posted, and storage is isolated.
func runTypingTestUISmokeTest(outputDirectory: URL? = nil) -> Bool {
    func fail(_ message: String) -> Bool { print("typing-test-ui-smoke: FAIL \(message)"); return false }
    guard Thread.isMainThread else { return fail("AppKit requires main thread") }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rimes-typing-ui-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = TypingTestHistoryStore(storageRoot: root)
        let input = TypingTestTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 140), textContainer: nil)
        input.acceptsTestInput = true
        input.isEditable = true
        var commits: [(String, Range<Int>?)] = []
        input.onCommittedText = { commits.append(($0, $1)) }
        input.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        input.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        guard commits.isEmpty, input.hasMarkedText() else {
            return fail("marked text protocol: commits=\(commits.count), text=\(input.string), marked=\(input.markedRange()), selected=\(input.selectedRange())")
        }
        input.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        guard commits.count == 1, commits[0].0 == "你好", commits[0].1 == 0..<2 else { return fail("IME commit must publish exactly once with actual range") }
        input.setSelectedRange(NSRange(location: 0, length: 1))
        input.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        guard commits.count == 2, commits.last?.1 == 0..<1 else { return fail("same-text replacement must remain observable") }
        input.setSelectedRange(NSRange(location: 2, length: 0))
        input.setMarkedText("hao", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        input.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        guard commits.count == 2, input.string == "你好" else { return fail("cancelled composition must not produce an attempt") }
        var assistance = 0
        input.onAssistedInput = { assistance += 1 }
        input.paste(nil)
        guard assistance == 1, input.string == "你好" else { return fail("paste must not mutate test") }
        input.insertText(String(repeating: "字", count: TypingTestSession.maximumCharacters + 1), replacementRange: NSRange(location: NSNotFound, length: 0))
        guard input.string == "你好", commits.count == 2 else { return fail("oversized commit must be rejected atomically") }

        let combining = TypingTestTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 140), textContainer: nil)
        combining.acceptsTestInput = true
        combining.isEditable = true
        let accentArticle = TypingTestArticle(id: "smoke.accent", version: 1, language: .english,
                                              title: "accent", theme: "fixture", difficulty: "fixture", text: "é")
        let accentSession = TypingTestSession(article: accentArticle, context: TypingTestContext(schemaID: "smoke"))
        var accentClock: TimeInterval = 1
        var accentAccepted = true
        combining.onCommittedText = { text, range in
            accentAccepted = accentAccepted && accentSession.reconcileCommittedText(text, at: accentClock, explicitInsertionRange: range)
        }
        combining.insertText("e", replacementRange: NSRange(location: NSNotFound, length: 0))
        accentClock = 2
        combining.insertText("\u{0301}", replacementRange: NSRange(location: NSNotFound, length: 0))
        guard accentAccepted, combining.string == "é",
              accentSession.snapshot(at: 3).metrics.correctCharacterCount == 1,
              accentSession.snapshot(at: 3).metrics.attemptedCharacterCount == 2 else {
            return fail("separate combining-mark commit must score the resulting grapheme")
        }

        let article = TypingTestArticles.defaultArticle
        let lifecycleStore = TypingTestHistoryStore(storageRoot: root.appendingPathComponent("lifecycle"))
        var clock: TimeInterval = 100
        let lifecycle = TypingSpeedSettingsViewController(
            subpageID: "overview", historyStore: lifecycleStore,
            contextProvider: { TypingTestContext(schemaID: "smoke-lifecycle") },
            clockProvider: { clock }, telemetryEnabled: false
        )
        _ = lifecycle.view
        lifecycle.smokeStartByButton()
        guard lifecycle.smokeIsArmed, lifecycle.smokeHasTimer,
              lifecycle.smokeSessionSnapshot?.isStarted == false,
              lifecycle.smokeSessionSnapshot?.metrics.elapsedSeconds == 0 else {
            return fail("start button must only arm the test")
        }
        guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                         timestamp: clock, windowNumber: 0, context: nil,
                                         characters: "a", charactersIgnoringModifiers: "a",
                                         isARepeat: false, keyCode: 0) else { return fail("local event fixture") }
        clock = 101
        lifecycle.practiceKey(key, isComposing: false)
        guard lifecycle.smokeSessionSnapshot?.isStarted == true,
              lifecycle.smokeSessionSnapshot?.metrics.physicalKeyCount == 1 else {
            return fail("first physical action must start timing")
        }
        clock = 161
        lifecycle.smokeEditor.insertText(article.text, replacementRange: NSRange(location: NSNotFound, length: 0))
        guard !lifecycle.smokeIsArmed, !lifecycle.smokeHasTimer,
              lifecycleStore.results.count == 1, lifecycleStore.results[0].isComplete else {
            return fail("complete commit must finish once and stop timer")
        }
        lifecycle.practiceKey(key, isComposing: false)
        lifecycle.smokeEditor.insertText("迟到", replacementRange: NSRange(location: NSNotFound, length: 0))
        lifecycle.smokeFinishByButton()
        guard lifecycleStore.results.count == 1, lifecycle.smokeEditor.string == article.text else {
            return fail("late input or duplicate finish must not rewrite results")
        }
        clock = 200
        lifecycle.smokeStartByButton()
        guard lifecycle.smokeEditor.string.isEmpty, lifecycle.smokeIsArmed,
              lifecycle.smokeHasTimer, lifecycle.smokeSessionSnapshot?.isStarted == false else {
            return fail("restart must clear editor and create a fresh armed session")
        }
        clock = 201
        lifecycle.practiceKey(key, isComposing: false)
        clock = 211
        lifecycle.smokeEditor.insertText(String(article.text.prefix(10)), replacementRange: NSRange(location: NSNotFound, length: 0))
        lifecycle.viewWillDisappear()
        guard !lifecycle.smokeIsArmed, !lifecycle.smokeHasTimer,
              lifecycleStore.results.count == 2,
              lifecycleStore.results.contains(where: { !$0.isComplete && $0.practiceReasons.contains(.interrupted) }) else {
            return fail("leaving the page must freeze an explicitly non-formal partial result")
        }
        clock = 300
        lifecycle.smokeStartByButton()
        lifecycle.practiceKey(key, isComposing: false)
        clock = 301
        lifecycle.smokeEditor.insertText(String(article.text.dropLast()), replacementRange: NSRange(location: NSNotFound, length: 0))
        // Simulate the NSTextView super.resignFirstResponder reentrant commit
        // between the real will-resign marker and its did-resign interruption.
        lifecycle.smokeEditor.onWillResignFocus?()
        clock = 311
        lifecycle.smokeEditor.insertText(String(article.text.suffix(1)), replacementRange: NSRange(location: NSNotFound, length: 0))
        lifecycle.smokeEditor.onFocusLost?()
        guard lifecycleStore.results.count == 3,
              lifecycleStore.results.contains(where: { $0.isComplete && $0.practiceReasons.contains(.focusLost) && !$0.isComparable }),
              !lifecycle.smokeHasTimer else {
            return fail("resign-time final commit must not become a formal result")
        }
        for number in 0..<4 {
            let session = TypingTestSession(article: article, context: TypingTestContext(schemaID: "smoke", mode: number == 0 ? .firstAttempt : .practice))
            session.start(at: 10)
            session.recordKey(at: 11)
            _ = session.reconcileCommittedText(article.text, at: 130 - Double(number) * 10)
            if let result = session.finish(at: 130 - Double(number) * 10, completedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(number) * 500)) {
                guard store.add(result) else { return fail("seed isolated result") }
            }
        }
        if let outputDirectory { try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true) }
        // Content areas the settings window can give a plugin page: the default
        // 980x680 window, its 860x600 minimum, and a large display.
        let sizes: [(name: String, size: NSSize)] = [("default", NSSize(width: 770, height: 500)),
                                                      ("minimum", NSSize(width: 650, height: 440)),
                                                      ("large", NSSize(width: 1180, height: 900))]
        for page in ["overview", "history"] {
            for (sizeName, size) in sizes {
                let controller = TypingSpeedSettingsViewController(subpageID: page, historyStore: store,
                                                                   library: TypingTestLibraryStore(storageRoot: root.appendingPathComponent("library-\(page)-\(sizeName)")))
                controller.prepareForSmoke(articleID: article.id, committedText: String(article.text.prefix(78)))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = RimeUI.appKitAppearance
                window.backgroundColor = RimeUI.surface
                window.setContentSize(size)
                let pane = controller.view
                // The settings shell supplies the page background; stand in for it here.
                let backdrop = TypingTestSmokeBackdrop(frame: NSRect(origin: .zero, size: size))
                window.contentView = backdrop
                backdrop.addSubview(pane)
                pane.frame = backdrop.bounds
                pane.autoresizingMask = [.width, .height]
                pane.layoutSubtreeIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                guard let scroll = controller.smokePageScroll, let document = scroll.documentView else {
                    return fail("\(page)/\(sizeName): page must be one scroll view")
                }
                func dump() -> String { "doc=\(document.frame) clip=\(scroll.contentView.bounds) editorScroll=\(String(describing: controller.smokeEditor.enclosingScrollView?.frame))" }
                guard document.frame.width >= scroll.contentView.bounds.width - 0.5 else { return fail("\(page)/\(sizeName): document narrower than viewport \(dump())") }
                // Short windows may scroll once; tall ones must fill with no outer scroll.
                if sizeName == "large" {
                    guard document.frame.height <= scroll.contentView.bounds.height + 0.5 else {
                        return fail("\(page)/\(sizeName): content must fill a tall window without scrolling \(dump())")
                    }
                }
                guard controller.smokeMaterialRowCount >= 9 else { return fail("material column must list the built-in articles") }
                if page == "overview" {
                    guard controller.smokeTargetString == article.text,
                          let editorScroll = controller.smokeEditor.enclosingScrollView,
                          let targetScroll = controller.smokeTargetScroll else { return fail("\(page)/\(sizeName): panels missing") }
                    let editorHeight = editorScroll.frame.height, targetHeight = targetScroll.frame.height
                    guard controller.smokeEditor.bounds.width > 300, editorHeight >= 60, targetHeight >= 80 else {
                        return fail("\(page)/\(sizeName): text panels collapsed editor=\(editorHeight) target=\(targetHeight) \(dump())")
                    }
                    if sizeName == "large" { guard targetHeight > 200 else { return fail("target panel must grow with the window: \(targetHeight)") } }
                }
                pane.displayIfNeeded()
                window.displayIfNeeded()
                guard let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else { return fail("bitmap surface") }
                backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]), !png.isEmpty else { return fail("PNG rendering") }
                if let outputDirectory {
                    let url = outputDirectory.appendingPathComponent("typing-test-\(page)-\(sizeName).png")
                    try png.write(to: url, options: .atomic)
                    print("typing-test-ui-smoke: rendered \(url.path)")
                }
                window.close()
            }
        }
        // Imported books: real import through the controller, then the column and
        // an imported passage rendered at the default size.
        do {
            let libraryRoot = root.appendingPathComponent("library-import")
            let importLibrary = TypingTestLibraryStore(storageRoot: libraryRoot)
            let file = root.appendingPathComponent("fixture.epub")
            try typingTestSmokeFixture().epub.write(to: file)
            let controller = TypingSpeedSettingsViewController(subpageID: "overview", historyStore: store, library: importLibrary,
                                                               contextProvider: { TypingTestContext(schemaID: "smoke-import") },
                                                               telemetryEnabled: false)
            let size = NSSize(width: 770, height: 500)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = RimeUI.appKitAppearance
            let backdrop = TypingTestSmokeBackdrop(frame: NSRect(origin: .zero, size: size))
            window.contentView = backdrop
            let pane = controller.view
            backdrop.addSubview(pane)
            pane.frame = backdrop.bounds
            pane.autoresizingMask = [.width, .height]
            let rowsBefore = controller.smokeMaterialRowCount
            controller.importFiles([file])
            let deadline = Date().addingTimeInterval(10)
            while importLibrary.books.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            guard let book = importLibrary.books.first else { return fail("import through the controller produced no book") }
            guard controller.smokeMaterialRowCount > rowsBefore, controller.smokeMaterials.currentArticleID == "epub.\(book.id).1",
                  controller.smokeTargetString == book.article(number: 1)?.text else {
                return fail("import must list the book and open its first passage: rows \(rowsBefore)->\(controller.smokeMaterialRowCount), current=\(String(describing: controller.smokeMaterials.currentArticleID))")
            }
            controller.importFiles([file])
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard importLibrary.books.count == 1 else { return fail("importing the same file twice must not duplicate it") }
            pane.layoutSubtreeIfNeeded(); pane.displayIfNeeded()
            if let outputDirectory, let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) {
                backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: outputDirectory.appendingPathComponent("typing-test-overview-book.png"), options: .atomic)
                }
            }
            window.close()
        }
        print("typing-test-ui-smoke: PASS marked/commit/cancel/replacement, input limits, article selection, history and default/minimum/large native layouts")
        return true
    } catch { return fail(error.localizedDescription) }
}

private final class TypingTestSmokeBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        RimeUI.surface.setFill()
        dirtyRect.fill()
    }
}
