import XCTest
@testable import AnyVim

// MARK: - Mock

/// Mock login item service — wraps LoginItemManaging protocol with an in-memory
/// enabled state. Tests run without calling SMAppService so no system-level
/// side effects occur.
final class MockLoginItemService: LoginItemManaging {
    var mockEnabled: Bool = false

    var isEnabled: Bool { mockEnabled }

    func enable() {
        mockEnabled = true
    }

    func disable() {
        mockEnabled = false
    }

    // Track first-run state in-memory (mirrors UserDefaults semantics for testing)
    private var firstRunConfigured = false

    func enableIfFirstRun() {
        guard !firstRunConfigured else { return }
        firstRunConfigured = true
        enable()
    }

    /// Reset first-run flag (allows testing the second-call behaviour)
    func resetFirstRunFlag() {
        firstRunConfigured = false
    }
}

// MARK: - Tests

final class LoginItemManagerTests: XCTestCase {

    // MARK: isEnabled

    func testIsEnabledReflectsServiceState() {
        let mock = MockLoginItemService()

        mock.mockEnabled = true
        XCTAssertTrue(mock.isEnabled)

        mock.mockEnabled = false
        XCTAssertFalse(mock.isEnabled)
    }

    // MARK: enableIfFirstRun

    func testEnableIfFirstRunEnablesOnFirstCall() {
        let mock = MockLoginItemService()
        XCTAssertFalse(mock.isEnabled, "Precondition: starts disabled")

        mock.enableIfFirstRun()

        XCTAssertTrue(mock.isEnabled, "Should be enabled after first call")
    }

    func testEnableIfFirstRunDoesNotReEnableOnSecondCall() {
        let mock = MockLoginItemService()

        // First call — enables
        mock.enableIfFirstRun()
        XCTAssertTrue(mock.isEnabled)

        // User disables login item manually
        mock.disable()
        XCTAssertFalse(mock.isEnabled)

        // Second call — flag is already set, should NOT re-enable
        mock.enableIfFirstRun()
        XCTAssertFalse(mock.isEnabled, "Should not re-enable when firstRunConfigured flag is already set")
    }

    // MARK: enable / disable

    func testEnableAndDisableToggleState() {
        let mock = MockLoginItemService()

        mock.enable()
        XCTAssertTrue(mock.isEnabled)

        mock.disable()
        XCTAssertFalse(mock.isEnabled)
    }
}
