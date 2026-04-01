import XCTest
@testable import AnyVim

// MARK: - Minimal mocks for MenuBarController construction in these tests

private final class StubPermissionChecker: PermissionChecking {
    var isAccessibilityGranted: Bool = false
    var isInputMonitoringGranted: Bool = false
    func openAccessibilitySettings() {}
    func openInputMonitoringSettings() {}
}

private final class StubLoginItemManager: LoginItemManaging {
    var isEnabled: Bool = false
    func enable() {}
    func disable() {}
    func enableIfFirstRun() {}
}

// MARK: - Tests

final class MenuBarControllerTests: XCTestCase {

    private var permissionStub: StubPermissionChecker!
    private var loginStub: StubLoginItemManager!
    private var controller: MenuBarController!

    override func setUp() {
        super.setUp()
        permissionStub = StubPermissionChecker()
        loginStub = StubLoginItemManager()
        controller = MenuBarController(
            permissionManager: permissionStub,
            loginItemManager: loginStub
        )
    }

    func testBuildMenuContainsQuitItem() {
        let menu = controller.buildMenu()
        let quitItem = menu.items.last
        XCTAssertEqual(quitItem?.title, "Quit AnyVim")
        XCTAssertEqual(quitItem?.keyEquivalent, "q")
    }

    func testBuildMenuContainsPermissionStatusItems() {
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.contains("Accessibility") }))
        XCTAssertTrue(titles.contains(where: { $0.contains("Input Monitoring") }))
    }

    func testBuildMenuContainsLaunchAtLoginItem() {
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Launch at Login"))
    }
}
