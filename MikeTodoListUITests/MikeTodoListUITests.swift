import XCTest

/// End-to-end smoke: app launches and shows the root Projects screen.
/// Extend with flow tests using accessibility identifiers as needed.
final class MikeTodoListUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// SwiftUI Form toggles often miss `.tap()`; probe success via the Repeat row appearing.
    private func tapReminderSwitchUntilExpanded(in app: XCUIApplication) {
        let reminderSwitch = app.switches.matching(identifier: "taskReminderToggle").element
        XCTAssertTrue(reminderSwitch.waitForExistence(timeout: 6))
        XCTAssertTrue(reminderSwitch.isHittable)

        let offsets: [CGFloat] = [0.15, 0.28, 0.42, 0.55, 0.72, 0.88]
        for dx in offsets {
            reminderSwitch.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            if app.staticTexts["Repeat"].waitForExistence(timeout: 2) {
                return
            }
        }

        XCTFail("Reminder toggle never expanded scheduling UI (Repeat row missing)")
    }

    func testLaunch_showsProjectsScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Projects"].waitForExistence(timeout: 8),
            "Expected root Projects navigation bar after launch"
        )
    }

    func testAddProject_displaysProject() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 8))

        let projectName = "UITest-\(Int(Date().timeIntervalSince1970))"
        app.buttons["Add project"].tap()

        let nameField = app.textFields["Project name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(projectName)

        app.buttons.matching(identifier: "addProjectConfirm").element.tap()

        XCTAssertTrue(
            app.staticTexts[projectName].waitForExistence(timeout: 5),
            "Expected newly added project to appear in the Projects list"
        )
    }

    func testAddTask_displaysTaskInProject() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 8))

        let suffix = Int(Date().timeIntervalSince1970)
        let projectName = "Tasks-\(suffix)"
        let taskName = "Task-\(suffix)"

        app.buttons["Add project"].tap()
        let projectField = app.textFields["Project name"]
        XCTAssertTrue(projectField.waitForExistence(timeout: 3))
        projectField.tap()
        projectField.typeText(projectName)
        app.buttons.matching(identifier: "addProjectConfirm").element.tap()

        let projectText = app.staticTexts[projectName]
        XCTAssertTrue(projectText.waitForExistence(timeout: 5))
        projectText.tap()

        XCTAssertTrue(app.navigationBars[projectName].waitForExistence(timeout: 5))
        app.buttons["Add task"].tap()

        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText(taskName)
        app.buttons["Done"].tap()

        XCTAssertTrue(
            app.staticTexts[taskName].waitForExistence(timeout: 5),
            "Expected newly added task to appear in the task list"
        )
    }

    /// Enables reminder UI, verifies scheduling-related controls appear, saves, and confirms reminder persists on the row.
    func testEnableReminder_showsBellOnTaskRowAndPersistsInEditor() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITestSkipNotifications")
        app.launch()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 8))

        let suffix = Int(Date().timeIntervalSince1970)
        let projectName = "Reminder-\(suffix)"
        let taskName = "AlphabetSoupQwerty"

        app.buttons["Add project"].tap()
        let projectField = app.textFields["Project name"]
        XCTAssertTrue(projectField.waitForExistence(timeout: 3))
        projectField.tap()
        projectField.typeText(projectName)
        app.buttons.matching(identifier: "addProjectConfirm").element.tap()

        XCTAssertTrue(app.staticTexts[projectName].waitForExistence(timeout: 5))
        app.staticTexts[projectName].tap()

        XCTAssertTrue(app.navigationBars[projectName].waitForExistence(timeout: 5))
        app.buttons["Add task"].tap()

        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.tap()
        titleField.typeText(taskName)

        let navBar = app.navigationBars.element(boundBy: 0)
        XCTAssertTrue(navBar.waitForExistence(timeout: 3))
        navBar.tap()

        let reminderSwitch = app.switches.matching(identifier: "taskReminderToggle").element
        for _ in 0..<10 {
            if reminderSwitch.waitForExistence(timeout: 1), reminderSwitch.isHittable {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(reminderSwitch.waitForExistence(timeout: 4))
        XCTAssertTrue(reminderSwitch.isHittable)
        tapReminderSwitchUntilExpanded(in: app)

        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts[taskName].waitForExistence(timeout: 6))

        let bellMarker = app.descendants(matching: .any)["taskRowReminder"]
        XCTAssertTrue(
            bellMarker.waitForExistence(timeout: 8),
            "Reminder UI path should persist reminderDate so the row shows the bell summary"
        )

        app.staticTexts[taskName].tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.staticTexts["Repeat"].waitForExistence(timeout: 6),
            "Saved reminder should show Repeat picker when reopening task details"
        )
    }
}
