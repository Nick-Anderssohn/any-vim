import XCTest
@testable import AnyVim

// MARK: - Mock

/// Mock permission checker — returns configurable booleans without calling
/// AXIsProcessTrusted() or CGPreflightListenEventAccess(), so these tests run
/// without requiring Accessibility or Input Monitoring TCC grants.
final class MockPermissionChecker: PermissionChecking {
    var isAccessibilityGranted: Bool
    var isInputMonitoringGranted: Bool

    // Track whether open methods were called
    var openAccessibilitySettingsCalled = false
    var openInputMonitoringSettingsCalled = false

    init(accessibility: Bool = false, inputMonitoring: Bool = false) {
        self.isAccessibilityGranted = accessibility
        self.isInputMonitoringGranted = inputMonitoring
    }

    func openAccessibilitySettings() {
        openAccessibilitySettingsCalled = true
    }

    func openInputMonitoringSettings() {
        openInputMonitoringSettingsCalled = true
    }
}

// MARK: - Tests

final class PermissionManagerTests: XCTestCase {

    // MARK: Accessibility

    func testAccessibilityGrantedReturnsTrue() {
        let mock = MockPermissionChecker(accessibility: true)
        XCTAssertTrue(mock.isAccessibilityGranted)
    }

    func testAccessibilityNotGrantedReturnsFalse() {
        let mock = MockPermissionChecker(accessibility: false)
        XCTAssertFalse(mock.isAccessibilityGranted)
    }

    // MARK: Input Monitoring

    func testInputMonitoringGrantedReturnsTrue() {
        let mock = MockPermissionChecker(inputMonitoring: true)
        XCTAssertTrue(mock.isInputMonitoringGranted)
    }

    func testInputMonitoringNotGrantedReturnsFalse() {
        let mock = MockPermissionChecker(inputMonitoring: false)
        XCTAssertFalse(mock.isInputMonitoringGranted)
    }

    // MARK: Open settings

    func testOpenAccessibilitySettingsInvokesMethod() {
        let mock = MockPermissionChecker()
        mock.openAccessibilitySettings()
        XCTAssertTrue(mock.openAccessibilitySettingsCalled)
    }

    func testOpenInputMonitoringSettingsInvokesMethod() {
        let mock = MockPermissionChecker()
        mock.openInputMonitoringSettings()
        XCTAssertTrue(mock.openInputMonitoringSettingsCalled)
    }
}
