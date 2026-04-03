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

    // MARK: - Vim path section tests (CONF-01)

    override func tearDown() {
        // Clean up any custom vim path set during tests
        UserDefaults.standard.removeObject(forKey: "customVimPath")
        UserDefaults.standard.removeObject(forKey: "copyExistingText")
        super.tearDown()
    }

    private func makeControllerWithVimResolver() -> MenuBarController {
        let stub = StubVimPathResolver()
        return MenuBarController(
            permissionManager: permissionStub,
            loginItemManager: loginStub,
            vimPathResolver: stub
        )
    }

    func testBuildMenuContainsVimPathInfoItem() {
        let ctrl = makeControllerWithVimResolver()
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains(where: { $0.hasPrefix("Vim:") }),
            "Menu should contain a 'Vim:' info item when vimPathResolver is set")
    }

    func testBuildMenuContainsSetVimPathItem() {
        let ctrl = makeControllerWithVimResolver()
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Set Vim Path..."),
            "Menu should always contain 'Set Vim Path...' when vimPathResolver is set")
    }

    func testBuildMenuShowsInvalidPathWhenCustomPathNotExecutable() {
        UserDefaults.standard.set("/nonexistent/path/vim", forKey: "customVimPath")
        let ctrl = makeControllerWithVimResolver()
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Vim: (custom path invalid)"),
            "Menu should show '(custom path invalid)' when custom path is not executable")
    }

    func testBuildMenuShowsResetItemWhenCustomPathSet() {
        UserDefaults.standard.set("/nonexistent/path/vim", forKey: "customVimPath")
        let ctrl = makeControllerWithVimResolver()
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Reset Vim Path"),
            "Menu should show 'Reset Vim Path' when a custom path is set")
    }

    func testBuildMenuOmitsResetItemWhenNoCustomPath() {
        UserDefaults.standard.removeObject(forKey: "customVimPath")
        let ctrl = makeControllerWithVimResolver()
        let menu = ctrl.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertFalse(titles.contains("Reset Vim Path"),
            "Menu should NOT show 'Reset Vim Path' when no custom path is set")
    }

    func testBuildMenuOmitsVimSectionWhenNoResolver() {
        // controller from setUp has no vimPathResolver
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertFalse(titles.contains("Set Vim Path..."),
            "Menu should NOT show vim path section when vimPathResolver is nil")
    }

    // MARK: - Copy Existing Text toggle tests

    func testBuildMenuContainsCopyExistingTextItem() {
        let menu = controller.buildMenu()
        let titles = menu.items.map { $0.title }
        XCTAssertTrue(titles.contains("Copy Existing Text"),
            "Menu should contain 'Copy Existing Text' item")
    }

    func testCopyExistingTextItemCheckedWhenEnabled() {
        UserDefaults.standard.register(defaults: ["copyExistingText": true])
        UserDefaults.standard.set(true, forKey: "copyExistingText")
        let menu = controller.buildMenu()
        let item = menu.items.first(where: { $0.title == "Copy Existing Text" })
        XCTAssertEqual(item?.state, .on,
            "Copy Existing Text item should be checked (.on) when UserDefaults value is true")
    }

    func testCopyExistingTextItemUncheckedWhenDisabled() {
        UserDefaults.standard.set(false, forKey: "copyExistingText")
        let menu = controller.buildMenu()
        let item = menu.items.first(where: { $0.title == "Copy Existing Text" })
        XCTAssertEqual(item?.state, .off,
            "Copy Existing Text item should be unchecked (.off) when UserDefaults value is false")
    }
}

// MARK: - StubVimPathResolver (for MenuBarControllerTests)

private final class StubVimPathResolver: VimPathResolving {
    var pathToReturn: String? = "/usr/bin/vim"
    func resolveVimPath() -> String? { return pathToReturn }
}
