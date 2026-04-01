import XCTest
import CoreGraphics
@testable import AnyVim

// MARK: - MockTapInstaller

/// Mock implementation of TapInstalling for unit tests.
/// Records calls and returns controllable results — no real CGEvent tap is created.
final class MockTapInstaller: TapInstalling {

    var createTapCalled = false
    var enableTapCalled = false
    var disableTapCalled = false

    /// Controls what createTap() returns. nil simulates failure (permissions denied).
    var tapToReturn: CFMachPort?

    /// Controls what isTapEnabled() returns.
    var tapEnabledResult = true

    func createTap(
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        createTapCalled = true
        return tapToReturn
    }

    func enableTap(_ tap: CFMachPort) {
        enableTapCalled = true
    }

    func isTapEnabled(_ tap: CFMachPort) -> Bool {
        return tapEnabledResult
    }

    func disableTap(_ tap: CFMachPort) {
        disableTapCalled = true
    }
}

// MARK: - HotkeyManagerTests

@MainActor
final class HotkeyManagerTests: XCTestCase {

    // keycodes matching Carbon HIToolbox constants
    private let kVKControl: Int = 0x3B
    private let kVKRightControl: Int = 0x3E
    private let kVKShift: Int = 0x38

    private var manager: HotkeyManager!
    private var mockTap: MockTapInstaller!

    override func setUp() {
        super.setUp()
        mockTap = MockTapInstaller()
        manager = HotkeyManager(tapInstaller: mockTap)
    }

    override func tearDown() {
        manager.tearDown()
        manager = nil
        mockTap = nil
        super.tearDown()
    }

    // MARK: - Double-tap state machine tests

    func testDoubleTapWithin350msFires() {
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }

        // First tap: down then up
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        // Second tap: down then up — within 350ms
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        XCTAssertEqual(triggerCount, 1, "onTrigger should fire exactly once on double-tap within 350ms")
    }

    func testDoubleTapOutside350msDoesNotFire() {
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }

        // First tap: down then up
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        // Exceed 350ms window
        Thread.sleep(forTimeInterval: 0.4)

        // Second tap: down then up — too slow
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        XCTAssertEqual(triggerCount, 0, "onTrigger should NOT fire when double-tap exceeds 350ms window")
    }

    func testSingleTapDoesNotFire() {
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }

        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        XCTAssertEqual(triggerCount, 0, "onTrigger should NOT fire on single tap")
    }

    func testHeldControlDoesNotFire() {
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }

        // Control down
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)

        // Hold for >350ms
        Thread.sleep(forTimeInterval: 0.4)

        // Control up — should reset to idle
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        // Now second tap — state was reset, this is a first tap, not second
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        XCTAssertEqual(triggerCount, 0, "onTrigger should NOT fire when Control is held >350ms")
    }

    func testInterveningKeyResetsStateMachine() {
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }

        // First Control tap
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        // Intervening Shift key press — resets state
        manager.handleFlagsChanged(flags: .maskShift, keycode: kVKShift)

        // Second Control tap — should not count because state was reset
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        XCTAssertEqual(triggerCount, 0, "onTrigger should NOT fire when an intervening non-Control key is pressed")
    }

    func testLeftAndRightControlFireTrigger() {
        var triggerCount = 0
        manager.onTrigger = { triggerCount += 1 }

        // First tap: Left Control
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKControl)

        // Second tap: Right Control — still counts as double-tap (D-02)
        manager.handleFlagsChanged(flags: .maskControl, keycode: kVKRightControl)
        manager.handleFlagsChanged(flags: CGEventFlags(rawValue: 0), keycode: kVKRightControl)

        XCTAssertEqual(triggerCount, 1, "Left + Right Control combination should fire onTrigger (both keycodes count)")
    }

    // MARK: - Tap installation tests

    func testInstallWithBothPermissionsGrantedCreatesTap() {
        let permissions = MockPermissionChecker(accessibility: true, inputMonitoring: true)

        manager.install(permissionManager: permissions)

        XCTAssertTrue(mockTap.createTapCalled, "install() should create tap when both permissions are granted")
    }

    func testInstallWithMissingAccessibilityDoesNotCreateTap() {
        let permissions = MockPermissionChecker(accessibility: false, inputMonitoring: true)

        manager.install(permissionManager: permissions)

        XCTAssertFalse(mockTap.createTapCalled, "install() should NOT create tap when Accessibility permission is missing")
    }

    func testInstallWithMissingInputMonitoringDoesNotCreateTap() {
        let permissions = MockPermissionChecker(accessibility: true, inputMonitoring: false)

        manager.install(permissionManager: permissions)

        XCTAssertFalse(mockTap.createTapCalled, "install() should NOT create tap when Input Monitoring permission is missing")
    }

    func testTearDownCleansUpTap() {
        // Just verify tearDown does not crash and resets state
        let permissions = MockPermissionChecker(accessibility: true, inputMonitoring: true)
        manager.install(permissionManager: permissions)

        manager.tearDown()

        XCTAssertFalse(manager.isTapHealthy, "isTapHealthy should be false after tearDown")
    }
}
