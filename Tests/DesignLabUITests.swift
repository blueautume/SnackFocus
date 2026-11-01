import XCTest

/// Real user-flow checks for the isolated style-lab branch. Rendering and
/// simulation correctness remain covered by the existing focused checks.
final class DesignLabUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 120
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--lab-theme=atelier", "--lab-form=clay"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["lab.schemes"].waitForExistence(timeout: 15))
        assertPairing("T01 / S06")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testLayoutAndSnakeCanChangeIndependently() {
        openSchemes()
        tapAfterScrolling(app.buttons["lab.theme.arcade"])
        closeSchemes()
        assertPairing("T03 / S06")

        openSchemes()
        tapAfterScrolling(app.buttons["Snakes · 10"], direction: .down)
        tapAfterScrolling(app.buttons["lab.form.pearl"])
        closeSchemes()
        assertPairing("T03 / S09")
    }

    func testFocusPauseResumeAndRestartConfirmation() {
        let primary = app.buttons["lab.primary"]
        assertLabel(primary, equals: "Start focus")
        tapAfterScrolling(primary)
        assertLabel(primary, equals: "Pause")

        primary.tap()
        assertLabel(primary, equals: "Resume")
        primary.tap()
        assertLabel(primary, equals: "Pause")

        tapAfterScrolling(app.buttons["lab.restart"])
        let alert = app.alerts["Restart?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        assertLabel(primary, equals: "Pause")
        XCTAssertTrue(app.buttons["lab.restart"].exists)

        app.buttons["lab.restart"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Restart"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        assertLabel(primary, equals: "Start focus")
        XCTAssertFalse(app.buttons["lab.restart"].exists)
        assertPairing("T01 / S06")
    }

    func testSavedPairingRestoresBothSelections() {
        openSchemes()
        let save = app.buttons["Save this pairing"]
        let wasAlreadySaved = app.buttons["Remove saved pairing"].exists
        if !wasAlreadySaved { tapAfterScrolling(save, direction: .down) }
        XCTAssertTrue(app.buttons["Remove saved pairing"].waitForExistence(timeout: 5))

        tapAfterScrolling(app.buttons["lab.theme.arcade"])
        tapAfterScrolling(app.buttons["Saved"], direction: .down)
        let savedCode = app.staticTexts["T01 / S06"].firstMatch
        tapAfterScrolling(savedCode)
        closeSchemes()
        assertPairing("T01 / S06")

        // Keep repeated smoke runs idempotent without deleting an existing
        // favorite from the test simulator's previous state.
        if !wasAlreadySaved {
            openSchemes()
            tapAfterScrolling(app.buttons["Remove saved pairing"], direction: .down)
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            closeSchemes()
        }
    }

    func testSettingsRestartPresentsConfirmationAfterSheetDismisses() {
        let primary = app.buttons["lab.primary"]
        tapAfterScrolling(primary)
        assertLabel(primary, equals: "Pause")

        openSettingsAndRequestRestart()
        let alert = app.alerts["Restart?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Game settings"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        assertLabel(primary, equals: "Pause")

        openSettingsAndRequestRestart()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Restart"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        assertLabel(primary, equals: "Start focus")
        assertPairing("T01 / S06")
    }

    private func openSettingsAndRequestRestart() {
        tapAfterScrolling(app.buttons["lab.settings"], direction: .down)
        XCTAssertTrue(app.navigationBars["Game settings"].waitForExistence(timeout: 5))
        tapAfterScrolling(app.buttons["lab.settings.restart"])
    }

    private func openSchemes() {
        tapAfterScrolling(app.buttons["lab.schemes"], direction: .down)
        XCTAssertTrue(app.navigationBars["Style lab"].waitForExistence(timeout: 5))
    }

    private func closeSchemes() {
        let done = app.navigationBars["Style lab"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.navigationBars["Style lab"].waitForNonExistence(timeout: 5))
    }

    private func assertPairing(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[value].firstMatch.waitForExistence(timeout: 5),
                      "Expected current pairing \(value)", file: file, line: line)
    }

    private func assertLabel(_ element: XCUIElement, equals value: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "Expected button label \(value), got \(element.label)", file: file, line: line)
    }

    private enum ScrollDirection { case up, down }

    private func tapAfterScrolling(_ element: XCUIElement, direction: ScrollDirection = .up,
                                   file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            let scrollView = app.scrollViews.firstMatch
            guard scrollView.exists else { break }
            if direction == .up { scrollView.swipeUp() }
            else { scrollView.swipeDown() }
        }
        XCTFail("Could not reach \(element)", file: file, line: line)
    }
}
