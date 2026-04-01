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

@MainActor
final class MockHotkeyManager: HotkeyManaging {
    var isTapHealthy: Bool
    var onTrigger: (() -> Void)?
    var onHealthChange: ((Bool) -> Void)?
    var installCalled = false
    var tearDownCalled = false

    init(tapHealthy: Bool = true) { self.isTapHealthy = tapHealthy }
    func install(permissionManager: PermissionChecking) { installCalled = true }
    func tearDown() { tearDownCalled = true }
}

// MARK: - Tests

@MainActor
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

    func testMenuShowsHotkeyActiveWhenTapHealthy() {
        let mockHotkey = MockHotkeyManager(tapHealthy: true)
        let ctrl = MenuBarController(
            permissionManager: permissionStub,
            loginItemManager: loginStub,
            hotkeyManager: mockHotkey
        )
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Hotkey: Active"), "Menu should contain 'Hotkey: Active' when tap is healthy")
    }

    func testMenuShowsHotkeyInactiveWhenTapUnhealthy() {
        let mockHotkey = MockHotkeyManager(tapHealthy: false)
        let ctrl = MenuBarController(
            permissionManager: permissionStub,
            loginItemManager: loginStub,
            hotkeyManager: mockHotkey
        )
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(
            titles.contains(where: { $0.contains("Inactive") }),
            "Menu should contain 'Inactive' item when tap is unhealthy"
        )
    }

    func testMenuOmitsHotkeyStatusWhenNoHotkeyManager() {
        // controller uses nil hotkeyManager (default setUp creates one without hotkey)
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertFalse(
            titles.contains(where: { $0.contains("Hotkey") }),
            "Menu should not contain any 'Hotkey' item when hotkeyManager is nil"
        )
    }
}
