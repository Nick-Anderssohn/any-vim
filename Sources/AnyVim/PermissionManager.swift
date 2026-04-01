import ApplicationServices
import CoreGraphics
import Foundation
import AppKit

// MARK: - Protocol for testability

protocol PermissionChecking {
    var isAccessibilityGranted: Bool { get }
    var isInputMonitoringGranted: Bool { get }
}

// MARK: - PermissionManager

final class PermissionManager: PermissionChecking {

    // MARK: - Live permission checks

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    var isInputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    // MARK: - Monitoring state

    private var pollTimer: Timer?
    private var previousAccessibility = false
    private var previousInputMonitoring = false

    // MARK: - Monitoring lifecycle

    /// Start monitoring permission changes.
    ///
    /// The onChange closure is called with `(accessibilityChanged, inputMonitoringChanged)`.
    /// Both booleans reflect whether the respective permission *changed* (not whether it is
    /// currently granted). The caller is responsible for reading live state after a change.
    func startMonitoring(onChange: @escaping (_ accessibilityChanged: Bool, _ inputMonitoringChanged: Bool) -> Void) {
        // Snapshot current state before we start watching
        previousAccessibility = isAccessibilityGranted
        previousInputMonitoring = isInputMonitoringGranted

        // DistributedNotificationCenter fires when TCC accessibility table changes.
        // Accessibility only — Input Monitoring has no equivalent notification.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkForChanges(onChange: onChange)
        }

        // Timer fallback — catches Input Monitoring changes and any missed accessibility
        // notifications. 3-second interval satisfies PERM-03 "within a few seconds".
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkForChanges(onChange: onChange)
        }
    }

    /// Stop monitoring permission changes.
    func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - System Settings URLs

    /// Open System Settings to the Accessibility privacy pane.
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    /// Open System Settings to the Input Monitoring privacy pane.
    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        )
    }

    // MARK: - Private helpers

    private func checkForChanges(onChange: @escaping (_ accessibilityChanged: Bool, _ inputMonitoringChanged: Bool) -> Void) {
        let currentAccessibility = isAccessibilityGranted
        let currentInputMonitoring = isInputMonitoringGranted

        let accessibilityChanged = currentAccessibility != previousAccessibility
        let inputMonitoringChanged = currentInputMonitoring != previousInputMonitoring

        if accessibilityChanged || inputMonitoringChanged {
            previousAccessibility = currentAccessibility
            previousInputMonitoring = currentInputMonitoring
            onChange(accessibilityChanged, inputMonitoringChanged)
        }
    }
}
