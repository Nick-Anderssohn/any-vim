import UserNotifications

// MARK: - NotificationManager

final class NotificationManager {

    // MARK: - Authorization

    /// Request notification authorization from the user.
    ///
    /// Must be called early in applicationDidFinishLaunching — without authorization,
    /// calls to UNUserNotificationCenter.add(_:) silently do nothing (Pitfall 6).
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Permission granted notification

    /// Post a macOS notification banner confirming a permission was granted (D-04).
    ///
    /// - Parameter permissionName: "Accessibility" or "Input Monitoring"
    func notifyPermissionGranted(_ permissionName: String) {
        let content = UNMutableNotificationContent()
        content.title = "AnyVim"
        content.body = "\(permissionName) permission granted."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
