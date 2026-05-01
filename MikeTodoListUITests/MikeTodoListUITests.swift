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
}
