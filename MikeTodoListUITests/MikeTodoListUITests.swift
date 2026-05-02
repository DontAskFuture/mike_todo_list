import XCTest

/// End-to-end smoke: app launches and shows the root Projects screen.
/// Extend with flow tests using accessibility identifiers as needed.
final class MikeTodoListUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
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

        app.buttons["Add"].tap()

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
        app.buttons["Add"].tap()

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
}
