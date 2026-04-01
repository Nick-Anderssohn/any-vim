import XCTest
@testable import AnyVim

final class MenuBarControllerTests: XCTestCase {
    func testBuildMenuContainsQuitItem() {
        let controller = MenuBarController()
        let menu = controller.buildMenu()
        let quitItem = menu.items.last
        XCTAssertEqual(quitItem?.title, "Quit AnyVim")
        XCTAssertEqual(quitItem?.keyEquivalent, "q")
    }

    func testBuildMenuContainsPermissionStatusItems() {
        let controller = MenuBarController()
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("Accessibility") }))
        XCTAssertTrue(titles.contains(where: { $0.contains("Input Monitoring") }))
    }

    func testBuildMenuContainsLaunchAtLoginItem() {
        let controller = MenuBarController()
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Launch at Login"))
    }
}
