import Carbon.HIToolbox
import CoreGraphics
import Foundation

// MARK: - TapInstalling protocol

/// Abstraction over the real CGEvent tap APIs, allowing tests to inject a mock.
protocol TapInstalling {
    func createTap(
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort?
    func enableTap(_ tap: CFMachPort)
    func isTapEnabled(_ tap: CFMachPort) -> Bool
    func disableTap(_ tap: CFMachPort)
}

// MARK: - SystemTapInstaller

/// Production implementation — wraps the real CoreGraphics CGEvent tap APIs.
struct SystemTapInstaller: TapInstalling {

    func createTap(
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        // Listen to flagsChanged events only — these fire on modifier key state changes
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        )
    }

    func enableTap(_ tap: CFMachPort) {
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func isTapEnabled(_ tap: CFMachPort) -> Bool {
        CGEvent.tapIsEnabled(tap: tap)
    }

    func disableTap(_ tap: CFMachPort) {
        CGEvent.tapEnable(tap: tap, enable: false)
    }
}

// MARK: - HotkeyManaging protocol

/// Public interface for the global hotkey detection system.
@MainActor
protocol HotkeyManaging: AnyObject {
    /// True when the CGEventTap is installed and currently enabled.
    var isTapHealthy: Bool { get }

    /// Called when a confirmed double-tap Control sequence is detected.
    var onTrigger: (() -> Void)? { get set }

    /// Called when tap health changes (true = healthy, false = degraded/gone).
    /// Used by MenuBarController to reflect tap status in the menu.
    var onHealthChange: ((Bool) -> Void)? { get set }

    /// Install the event tap, guarded by permission checks.
    func install(permissionManager: PermissionChecking)

    /// Remove the event tap and health timer. Safe to call multiple times.
    func tearDown()
}

// MARK: - Double-tap state machine

/// States for the Control double-tap detector.
private enum DoubleTapState {
    case idle
    case firstTapDown(at: TimeInterval)
    case firstTapUp(at: TimeInterval)
    case secondTapDown
}

// MARK: - HotkeyManager

@MainActor
final class HotkeyManager: HotkeyManaging {

    // MARK: - Configuration

    /// Virtual keycodes for left and right Control (per D-02: both count).
    private let controlKeycodes: Set<Int> = [Int(kVK_Control), Int(kVK_RightControl)]

    /// Maximum interval (seconds) between tap-up and the next tap-down (D-03).
    private let doubleTapThreshold: TimeInterval = 0.350

    /// Maximum duration a key may be held down before the first-tap is discarded.
    private let holdThreshold: TimeInterval = 0.350

    /// How often to check tap health (D-08).
    private let healthCheckInterval: TimeInterval = 5.0

    // MARK: - Injected

    private let tapInstaller: TapInstalling

    // MARK: - State

    private var state: DoubleTapState = .idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?

    // MARK: - Public properties

    private(set) var isTapHealthy: Bool = false {
        didSet {
            if isTapHealthy != oldValue {
                onHealthChange?(isTapHealthy)
            }
        }
    }

    var onTrigger: (() -> Void)?
    var onHealthChange: ((Bool) -> Void)?

    // MARK: - Init

    init(tapInstaller: TapInstalling = SystemTapInstaller()) {
        self.tapInstaller = tapInstaller
    }

    // MARK: - HotkeyManaging

    func install(permissionManager: PermissionChecking) {
        guard permissionManager.isAccessibilityGranted,
              permissionManager.isInputMonitoringGranted else {
            return
        }
        installTap()
        startHealthMonitor()
    }

    func tearDown() {
        healthTimer?.invalidate()
        healthTimer = nil
        tearDownTap()
    }

    // MARK: - State machine (called from main queue via DispatchQueue.main.async in callback)

    /// Process a flagsChanged event. Called on the main queue.
    ///
    /// - Parameters:
    ///   - flags: The modifier flags from the event.
    ///   - keycode: The hardware keycode (kVK_Control = 0x3B, kVK_RightControl = 0x3E).
    func handleFlagsChanged(flags: CGEventFlags, keycode: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        let isControlKey = controlKeycodes.contains(keycode)
        let isControlDown = flags.contains(.maskControl)

        // Any non-Control modifier key resets the state machine (D-04)
        if !isControlKey {
            state = .idle
            return
        }

        switch state {
        case .idle:
            if isControlDown {
                state = .firstTapDown(at: now)
            }

        case .firstTapDown(let downAt):
            if !isControlDown {
                // Key released
                let held = now - downAt
                if held > holdThreshold {
                    // Held too long — treat as intentional hold, reset (D-05)
                    state = .idle
                } else {
                    state = .firstTapUp(at: now)
                }
            }
            // Still down — no state change (could be repeat events)

        case .firstTapUp(let upAt):
            if isControlDown {
                // Second tap begins
                let gap = now - upAt
                if gap <= doubleTapThreshold {
                    state = .secondTapDown
                } else {
                    // Too slow — this is a new first tap
                    state = .firstTapDown(at: now)
                }
            }

        case .secondTapDown:
            if !isControlDown {
                // Second tap completed — fire!
                state = .idle
                onTrigger?()
            }
        }
    }

    /// Handle a disabled-tap event. Called on the main queue.
    func handleTapDisabled() {
        guard let tap = eventTap else { return }
        tapInstaller.enableTap(tap)
        isTapHealthy = tapInstaller.isTapEnabled(tap)
    }

    // MARK: - Tap lifecycle

    private func installTap() {
        // Capture unretained self for the C callback (retained by the run loop)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = tapInstaller.createTap(
            callback: hotkeyEventTapCallback,
            userInfo: selfPtr
        ) else {
            isTapHealthy = false
            return
        }

        eventTap = tap
        tapInstaller.enableTap(tap)

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        isTapHealthy = tapInstaller.isTapEnabled(tap)
    }

    /// Remove the run loop source first, then nil out the tap reference.
    /// (Anti-pattern: never nil the tap before removing its run loop source.)
    private func tearDownTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        isTapHealthy = false
    }

    // MARK: - Health monitor

    private func startHealthMonitor() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(
            withTimeInterval: healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            // Timer fires on the run loop thread; bounce to MainActor
            Task { @MainActor [weak self] in
                self?.checkTapHealth()
            }
        }
    }

    private func checkTapHealth() {
        guard let tap = eventTap else {
            isTapHealthy = false
            return
        }

        if tapInstaller.isTapEnabled(tap) {
            isTapHealthy = true
            return
        }

        // Try a simple re-enable first
        tapInstaller.enableTap(tap)
        if tapInstaller.isTapEnabled(tap) {
            isTapHealthy = true
            return
        }

        // Re-enable failed (code-signing identity changed, etc.) — full reinstall (D-08)
        tearDownTap()
        installTap()
    }
}

// MARK: - Global C callback

/// C-compatible event tap callback. Nonisolated (free function) per Swift 6 rules.
/// All MainActor state mutation is dispatched to the main queue.
private func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else {
        return Unmanaged.passRetained(event)
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DispatchQueue.main.async {
            manager.handleTapDisabled()
        }

    case .flagsChanged:
        let flags = event.flags
        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        DispatchQueue.main.async {
            manager.handleFlagsChanged(flags: flags, keycode: keycode)
        }

    default:
        break
    }

    // Observe only — do not consume events (D-07)
    return Unmanaged.passRetained(event)
}
