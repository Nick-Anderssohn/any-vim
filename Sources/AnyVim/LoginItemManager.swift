import Foundation
import ServiceManagement

// MARK: - Protocol for testability

protocol LoginItemManaging {
    var isEnabled: Bool { get }
    func enable()
    func disable()
    func enableIfFirstRun()
}

// MARK: - LoginItemManager

final class LoginItemManager: LoginItemManaging {

    // MARK: - Live status

    /// Read live from the OS — NEVER cache in UserDefaults.
    /// Users can remove login items via System Settings > General > Login Items;
    /// the OS is always the source of truth.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    // MARK: - Toggle

    func enable() {
        try? SMAppService.mainApp.register()
    }

    func disable() {
        try? SMAppService.mainApp.unregister()
    }

    // MARK: - First-run default

    /// Enable launch at login on first run only (D-07).
    ///
    /// Uses a UserDefaults flag to detect first run. If the flag has not been set,
    /// this is the first launch — enable the login item and record the flag so
    /// subsequent launches do not re-enable it if the user later disables it.
    func enableIfFirstRun() {
        let key = "launchAtLoginConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        enable()
    }
}
