import XCTest

/// Evidence-pack driver: screenshots of the flows the readiness docs cite.
/// Runs only when EVIDENCE_DIR is set, so a plain UI-test run skips it.
/// Env (via TEST_RUNNER_ prefix):
///   EVIDENCE_DIR, EVIDENCE_PREFIX, EVIDENCE_ORIENT (portrait|landscape)
final class EvidenceCaptureUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var dir: String { env["EVIDENCE_DIR"] ?? "/tmp/evidence" }
    private var prefix: String { env["EVIDENCE_PREFIX"] ?? "shot" }

    override func setUpWithError() throws {
        try XCTSkipIf(env["EVIDENCE_DIR"] == nil, "Set TEST_RUNNER_EVIDENCE_DIR to capture evidence.")
        continueAfterFailure = true
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if env["EVIDENCE_ORIENT"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
        } else {
            XCUIDevice.shared.orientation = .portrait
        }
    }

    private func settle(_ s: TimeInterval = 1.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(s))
    }

    private func shot(_ name: String) {
        settle()
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let path = "\(dir)/\(prefix)-\(name).png"
        FileManager.default.createFile(atPath: path, contents: data)
    }

    private func log(_ s: String) {
        let path = "\(dir)/\(prefix)-log.txt"
        let line = s + "\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    private func dismissKeyboardIntro(_ app: XCUIApplication) {
        let intro = app.otherElements["UIContinuousPathIntroductionView"]
        if intro.waitForExistence(timeout: 2) { intro.buttons["Continue"].tap() }
    }

    private func launchWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()
        return app
    }

    /// Lands on the PIN lock (PIN 4829), onboarding already complete.
    private func launchLocked() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SeedUpgradeFixture"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()
        _ = app.buttons["PIN digit 1 of 4"].waitForExistence(timeout: 20)
        return app
    }

    private func unlock(_ app: XCUIApplication) {
        settle(1)
        enterLockPIN("4829", in: app)
        dismissKeyboardIntro(app)
        if app.buttons["PIN digit 1 of 4"].exists {
            settle(1)
            if app.buttons["PIN digit 1 of 4"].exists { enterLockPIN("4829", in: app) }
        }
        _ = app.buttons["Menu"].waitForExistence(timeout: 15)
        settle(2)
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["Menu"].firstMatch.tap()
        let row = app.buttons["profile.settings"].firstMatch
        if row.waitForExistence(timeout: 10) { row.tap() } else { log("profile.settings missing") }
        settle(1.5)
    }

    private func openChat(_ app: XCUIApplication) {
        let chat = app.buttons["AI chat"].firstMatch
        if chat.waitForExistence(timeout: 5), chat.isHittable { chat.tap() } else { app.swipeLeft() }
        settle(2)
    }

    private func loadSamples(_ app: XCUIApplication) {
        openSettings(app)
        let sample = app.buttons["settings.sampleEntries"].firstMatch
        var tries = 0
        while !(sample.exists && sample.isHittable) && tries < 8 {
            app.swipeUp(); tries += 1
        }
        if sample.exists {
            if sample.label.contains("Load") || app.staticTexts["Load Sample Entries"].exists {
                sample.tap()
                settle(4)
            }
        } else {
            log("settings.sampleEntries missing")
        }
    }

    // MARK: Full light/dark set

    func test_full() {
        var app = launchWelcome()
        _ = app.buttons["welcome.getStarted"].waitForExistence(timeout: 30)
        settle(4)
        shot("welcome")
        app.terminate()

        app = launchLocked()
        shot("lock")
        unlock(app)
        shot("journal-empty")

        openSettings(app)
        shot("settings")
        app.terminate()

        app = launchLocked()
        unlock(app)
        loadSamples(app)
        app.terminate()

        app = launchLocked()
        unlock(app)
        shot("journal")

        openChat(app)
        if app.otherElements["chat.unavailable"].exists || app.descendants(matching: .any)["chat.unavailable"].exists {
            shot("chat-unavailable")
            log("chat: unavailable state shown")
        } else {
            shot("chat")
            log("chat: composer available")
            if env["EVIDENCE_ASK"] == "1" {
                let composer = app.buttons["Chat with Memento"]
                if composer.waitForExistence(timeout: 10) {
                    composer.tap()
                    dismissKeyboardIntro(app)
                    app.typeText("What did I write about the rain?")
                    let send = app.buttons["Send message"]
                    if send.waitForExistence(timeout: 5) { send.tap() }
                    let done = app.buttons["chat.reply.thumbsUp"].firstMatch
                    let ok = done.waitForExistence(timeout: 120)
                    log("ask reply finished: \(ok)")
                    settle(2)
                    shot("chat-ask")
                }
            }
        }
        app.terminate()

        app = launchLocked()
        unlock(app)
        app.buttons["Menu"].firstMatch.tap()
        settle(1.5)
        let weekly = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Weekly'")).firstMatch
        if weekly.waitForExistence(timeout: 10) {
            weekly.tap(); settle(3); shot("weekly")
            app.terminate()
            app = launchLocked(); unlock(app)
            app.buttons["Menu"].firstMatch.tap(); settle(1.5)
        } else { log("Weekly row missing"); shot("menu-debug") }
        let patterns = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Patterns'")).firstMatch
        if patterns.waitForExistence(timeout: 10) {
            patterns.tap(); settle(3); shot("patterns")
        } else { log("Patterns row missing") }
        app.terminate()

        app = launchLocked()
        unlock(app)
        app.buttons["Search"].firstMatch.tap()
        settle(2)
        shot("search")
    }

    // MARK: Reduce Transparency set (samples already loaded)

    func test_reduceTransparency() {
        var app = launchWelcome()
        _ = app.buttons["welcome.getStarted"].waitForExistence(timeout: 30)
        settle(4)
        shot("welcome")
        app.terminate()

        app = launchLocked()
        unlock(app)
        shot("journal-header-fab")
        openChat(app)
        shot("chat-composer")
        let composer = app.buttons["Chat with Memento"]
        if composer.waitForExistence(timeout: 5) {
            composer.tap(); dismissKeyboardIntro(app); settle(1)
            app.typeText("Draft")
            shot("chat-composer-active")
        }
    }

    // MARK: AX5 set (samples already loaded)

    func test_ax5() {
        var app = launchLocked()
        shot("lock")
        unlock(app)
        openSettings(app)
        shot("settings")
        app.swipeUp(); settle(1)
        shot("settings-scrolled")
        app.terminate()

        app = launchLocked()
        unlock(app)
        openChat(app)
        shot("chat")
        app.terminate()

        app = launchLocked()
        unlock(app)
        app.buttons["Search"].firstMatch.tap()
        settle(2)
        shot("search")
        app.typeText("rain")
        settle(2)
        shot("search-results")
    }

    // MARK: Dictation indicator

    private func allowSystemPrompts() {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let allow = sb.buttons["Allow"]
            if allow.waitForExistence(timeout: 3) {
                log("system prompt: \(sb.alerts.firstMatch.label)")
                allow.tap(); settle(1)
            } else { break }
        }
    }

    func test_dictation() {
        var app = launchLocked()
        unlock(app)
        let fab = app.buttons["journal.newEntryFAB"].firstMatch
        if fab.waitForExistence(timeout: 10) { fab.tap() } else { log("FAB missing") }
        settle(2)
        dismissKeyboardIntro(app)
        let mic = app.buttons["journal.entryEditor.mic"].firstMatch
        if mic.waitForExistence(timeout: 10) {
            shot("add-entry-idle")
            mic.tap()
            allowSystemPrompts()
            if app.alerts.firstMatch.exists {
                log("add-entry alert after allow: \(app.alerts.firstMatch.label)")
                app.alerts.firstMatch.buttons.element(boundBy: 0).tap(); settle(1)
                mic.tap(); allowSystemPrompts()
            }
            settle(2.5)
            for a in app.alerts.allElementsBoundByIndex { log("alert: \(a.label)") }
            shot("add-entry-dictating")
            log("add-entry mic label after tap: \(mic.label)")
            settle(3)
            shot("add-entry-dictating-5s")
        } else { log("entry mic missing") }
        app.terminate()

        app = launchLocked()
        unlock(app)
        openChat(app)
        let dictate = app.buttons["Dictate"].firstMatch
        if dictate.waitForExistence(timeout: 10) {
            shot("ask-idle")
            dictate.tap()
            allowSystemPrompts()
            settle(2.5)
            for a in app.alerts.allElementsBoundByIndex { log("alert: \(a.label)") }
            shot("ask-dictating")
            log("ask insert-dictated exists: \(app.buttons["Insert dictated text"].exists)")
            settle(3)
            shot("ask-dictating-5s")
        } else { log("Dictate button missing") }
    }

    // MARK: Layout measurements (iPad column + nav gap)

    private func f(_ r: CGRect) -> String {
        String(format: "x=%.1f..%.1f (w %.1f) y=%.1f..%.1f", r.minX, r.maxX, r.width, r.minY, r.maxY)
    }

    private func dumpFrames(_ app: XCUIApplication, _ tag: String) {
        log("== \(tag) window \(f(app.windows.firstMatch.frame))")
        for (i, nb) in app.navigationBars.allElementsBoundByIndex.enumerated() where nb.exists {
            log("navbar[\(i)] '\(nb.identifier)' \(f(nb.frame)) hittable=\(nb.isHittable)")
        }
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(12)
        for t in texts where t.exists && t.frame.height > 0 {
            log("text '\(t.label.prefix(40))' \(f(t.frame))")
        }
        let cells = app.buttons.allElementsBoundByIndex.prefix(40)
        for b in cells where b.exists && b.frame.width > 150 {
            log("wide button '\(b.identifier)' '\(b.label.prefix(30))' \(f(b.frame))")
        }
        for id in ["journal.newEntryFAB", "Chat with Memento", "Dictate", "Send message"] {
            let e = app.buttons[id].firstMatch
            if e.exists { log("\(id) \(f(e.frame))") }
        }
        for sv in app.scrollViews.allElementsBoundByIndex where sv.exists {
            log("scrollView \(f(sv.frame))")
        }
    }

    func test_gap() {
        let app = launchLocked()
        unlock(app)
        for nb in app.navigationBars.allElementsBoundByIndex where nb.exists { log("navbar \(f(nb.frame))") }
        let menu = app.buttons["Menu"].firstMatch
        log("Menu button \(f(menu.frame))")
        let hdr = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'July 2026'"))
        for e in hdr.allElementsBoundByIndex where e.exists { log("header '\(e.label)' type=\(e.elementType.rawValue) \(f(e.frame))") }
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Journal card'")).firstMatch
        log("first card \(f(card.frame))")
    }

    func test_measure() {
        var app = launchLocked()
        unlock(app)
        dumpFrames(app, "journal")
        openChat(app)
        dumpFrames(app, "chat")
        app.terminate()
        app = launchLocked()
        unlock(app)
        openSettings(app)
        dumpFrames(app, "settings")
    }

    // MARK: Journal <-> Chat swipe (paired with an external screen recording)

    func test_swipe() {
        let app = launchLocked()
        unlock(app)
        settle(1)
        for _ in 0..<2 {
            app.swipeLeft(); settle(2)
            let journal = app.buttons["Journal"].firstMatch
            if journal.exists { journal.tap() } else { app.swipeRight() }
            settle(2)
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: mid, withVelocity: 150, thenHoldForDuration: 2)
        settle(2)
    }
}
