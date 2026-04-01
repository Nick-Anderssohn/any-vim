# Architecture Patterns

**Domain:** macOS system-wide editor utility (menu bar app)
**Project:** AnyVim
**Researched:** 2026-03-31

## Recommended Architecture

AnyVim maps cleanly onto five distinct components with a linear data flow during the edit cycle, bookended by a persistent background layer.

```
┌──────────────────────────────────────────────────────────┐
│                    AppShell (persistent)                  │
│  NSStatusItem + NSMenu + PermissionGuard                 │
└─────────────────────────┬────────────────────────────────┘
                          │ starts / owns
                          ▼
┌──────────────────────────────────────────────────────────┐
│                  HotkeyMonitor                           │
│  CGEventTap on runloop — double-tap Control detection    │
└─────────────────────────┬────────────────────────────────┘
                          │ fires EditCycleCoordinator
                          ▼
┌──────────────────────────────────────────────────────────┐
│               EditCycleCoordinator                       │
│  Orchestrates the full grab → edit → paste sequence      │
└───┬──────────────────┬──────────────────────┬────────────┘
    │                  │                      │
    ▼                  ▼                      ▼
┌────────────┐  ┌─────────────────┐  ┌──────────────────┐
│Accessibility│ │  TempFileStore  │  │  VimLauncher     │
│Bridge      │ │  /tmp/anyvim/   │  │  Process + wait  │
│read / paste│ │  write / read   │  │  SwiftTerm or    │
└────────────┘ └─────────────────┘  │  Process+open    │
                                    └──────────────────┘
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **AppShell** | NSStatusItem lifecycle, menu, permission checks at startup, launching HotkeyMonitor | HotkeyMonitor (owns), PermissionGuard |
| **PermissionGuard** | AXIsProcessTrusted + IOHIDCheckAccess checks; prompts user; blocks EditCycle if not granted | AppShell (called by), EditCycleCoordinator (gate) |
| **HotkeyMonitor** | CGEventTap on a dedicated CFRunLoop thread; double-tap timing state machine; fires callback | EditCycleCoordinator (calls), AppShell (owned by) |
| **EditCycleCoordinator** | Single-use per invocation: sequences AccessibilityBridge read → TempFileStore write → VimLauncher launch → wait → TempFileStore read → AccessibilityBridge paste; owns clipboard save/restore | All three sub-components |
| **AccessibilityBridge** | AXUIElement focused-element lookup; Cmd+A / Cmd+C synthesis to read; Cmd+A / Cmd+V synthesis to paste; NSPasteboard snapshot/restore | OS accessibility layer, NSPasteboard |
| **TempFileStore** | Write initial content to `/tmp/anyvim/<uuid>.txt`; read back after edit; delete after paste | EditCycleCoordinator |
| **VimLauncher** | Spawn vim process in a terminal (SwiftTerm-hosted NSWindow or Terminal.app fallback); block until Process terminates | TempFileStore (temp file path), OS process layer |

---

## Data Flow

### Normal Edit Cycle

```
User double-taps Control
        │
        ▼
HotkeyMonitor detects second tap within ~350ms window
        │
        ▼
EditCycleCoordinator.begin()
        │
        ├─ 1. AccessibilityBridge.readFocusedText()
        │       AXUIElement → focused element → Cmd+A + Cmd+C → NSPasteboard.string
        │       (snapshot original clipboard first for later restore)
        │
        ├─ 2. TempFileStore.write(text)
        │       write string → /tmp/anyvim/<uuid>.txt
        │
        ├─ 3. VimLauncher.launch(fileURL:)
        │       spawn SwiftTerm window running `vim /tmp/anyvim/<uuid>.txt`
        │       block (Process.waitUntilExit or terminationHandler)
        │
        ├─ 4. TempFileStore.read() → editedText
        │       read file contents after vim exits
        │
        ├─ 5. AccessibilityBridge.paste(editedText)
        │       set NSPasteboard → focused element → Cmd+A + Cmd+V
        │
        ├─ 6. AccessibilityBridge.restoreClipboard()
        │       restore original NSPasteboard snapshot
        │
        └─ 7. TempFileStore.delete()
                unlink temp file
```

### Information flows

| Transfer | Mechanism | Direction |
|----------|-----------|-----------|
| Focused element text → app | AXUIElement + NSPasteboard (Cmd+C synthesized) | target app → AnyVim |
| Text → vim | `/tmp/anyvim/<uuid>.txt` file write | AnyVim → filesystem |
| vim edits → app | file read after vim exit, NSPasteboard (Cmd+V synthesized) | filesystem → AnyVim → target app |
| Original clipboard | NSPasteboard snapshot before Cmd+C, restore after Cmd+V | AnyVim → NSPasteboard |
| Double-tap signal | CGEventTap callback, timestamp comparison in HotkeyMonitor | OS → AnyVim |
| Permission state | AXIsProcessTrusted() + IOHIDCheckAccess() at launch | OS → AppShell |

---

## Patterns to Follow

### Pattern 1: CGEventTap on a Dedicated Thread

Run the CGEventTap on its own CFRunLoop thread, not the main thread. The main thread is reserved for AppKit UI updates (NSStatusItem menu). Keyboard events must not block the UI and vice versa.

```swift
// Pseudocode — actual implementation verified against Apple docs
let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: hotkeyCallback,
    userInfo: nil
)!
let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
let tapRunLoop = CFRunLoopCreate()   // dedicated loop, not main
CFRunLoopAddSource(tapRunLoop, source, .commonModes)
CFRunLoopRun()  // on background thread
```

**Confidence:** MEDIUM — pattern established from CGEventTap documentation and community implementations (EventTapper, alt-tab-macos).

### Pattern 2: Double-Tap State Machine in HotkeyMonitor

Track last-keydown timestamp and keycode. On each Control keydown, compare against stored timestamp. Fire if within threshold (~350ms). Reset state after fire or timeout.

```swift
// State (on tap thread — no shared state with main)
var lastControlDown: CFAbsoluteTime = 0

func hotkeyCallback(event: CGEvent) {
    guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 59 /* Control */ else { return }
    let now = CFAbsoluteTimeGetCurrent()
    if now - lastControlDown < 0.35 {
        // double-tap — dispatch to coordinator
        DispatchQueue.main.async { EditCycleCoordinator.shared.begin() }
        lastControlDown = 0
    } else {
        lastControlDown = now
    }
}
```

**Confidence:** MEDIUM — timing threshold typical for double-tap detection; exact keycode for Control (59) confirmed via community implementations.

### Pattern 3: EditCycle as Async/Await Sequence

Use Swift async/await for the edit cycle. Each step is `async throws`. VimLauncher wraps `Process.terminationHandler` in a `withCheckedThrowingContinuation`. This keeps the coordinator linear and readable while avoiding blocking the main thread.

```swift
func begin() async throws {
    let original = try await accessibilityBridge.readFocusedText()  // async w/ clipboard snapshot
    let fileURL  = try tempFileStore.write(original)
    try await vimLauncher.launch(fileURL: fileURL)          // returns after :wq
    let edited   = try tempFileStore.read(fileURL)
    try await accessibilityBridge.paste(edited)
    accessibilityBridge.restoreClipboard()
    tempFileStore.delete(fileURL)
}
```

### Pattern 4: VimLauncher — SwiftTerm First, Process+open Fallback

Preferred: embed SwiftTerm (a VT100/xterm Swift library) in a borderless NSWindow. Vim runs inside it. Window closes on vim exit. This avoids Terminal.app focus stealing and is fully controllable.

Fallback: `Process` to open Terminal.app with a wrapper script that removes the temp file as its sentinel for completion detection. This is simpler to implement but has race condition risk.

**Recommendation:** SwiftTerm for v1. It provides a clean modal experience and eliminates Terminal.app complexity. SwiftTerm is a maintained, MIT-licensed Swift package.

**Confidence:** MEDIUM — SwiftTerm existence and capability verified via GitHub (github.com/migueldeicaza/SwiftTerm). Integration complexity not fully assessed; flag for research during VimLauncher phase.

### Pattern 5: NSPasteboard Snapshot/Restore

Before reading the text field with Cmd+C, snapshot all current pasteboard items by type. After pasting with Cmd+V, write the snapshot back. This is the only reliable way to preserve clipboard. NSPasteboard does not have a built-in "undo" operation.

```swift
// Snapshot
let types = pasteboard.types ?? []
let items = types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
    guard let data = pasteboard.data(forType: type) else { return nil }
    return (type, data)
}

// Restore
pasteboard.clearContents()
for (type, data) in items {
    pasteboard.setData(data, forType: type)
}
```

**Confidence:** HIGH — NSPasteboard API is stable and well-documented by Apple.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Running CGEventTap on the Main Thread

**What:** Installing the event tap source into the main RunLoop.
**Why bad:** AppKit events also run on the main RunLoop. Under load, key events can queue behind UI work and be processed with visible lag. Worse, a blocking accessibility call during an edit cycle will freeze the event tap.
**Instead:** Dedicated CFRunLoop thread for the tap. Dispatch back to main only for UI operations (menu updates, permission dialogs).

### Anti-Pattern 2: Using NSEvent.addGlobalMonitorForEvents Instead of CGEventTap

**What:** NSEvent global monitors are simpler to set up than CGEventTap.
**Why bad:** NSEvent monitors cannot suppress (swallow) events — they are always passive. If AnyVim ever needs to consume the double-tap Control without forwarding it, NSEvent cannot do this. Also, NSEvent monitors require Accessibility permission; CGEventTap requires Input Monitoring, which is compatible with future sandboxing requirements.
**Instead:** CGEventTap with `.defaultTap` option. Lets events pass through by returning the unmodified event; swallowing is available if needed later.

### Anti-Pattern 3: Polling for Vim Exit via Timer

**What:** Launching vim and polling a timer to check if the process is still running.
**Why bad:** Race conditions — file may not be fully flushed when the timer fires. Timer interval adds perceptible latency.
**Instead:** `Process.terminationHandler` or `waitUntilExit()` on a background thread. Zero-latency reaction to vim exit.

### Anti-Pattern 4: Direct AXUIElementSetAttributeValue for Pasting

**What:** Writing text directly into the focused AXUIElement's value attribute.
**Why bad:** Many apps (browsers, Electron apps, native text views) mark their text fields as read-only in the accessibility tree even though they accept keyboard input. Direct value-setting fails silently on these.
**Instead:** Synthesize Cmd+A + Cmd+V keystrokes via CGEvent after placing text on the pasteboard. Works across virtually all apps that accept text input.

### Anti-Pattern 5: Launching Terminal.app for Vim

**What:** Using `open -a Terminal` or AppleScript to launch vim in Terminal.app.
**Why bad:** No reliable mechanism to detect Terminal.app closure that corresponds to this specific vim session. User may have other Terminal windows open. AppleScript scripting of Terminal is fragile and slow. Terminal.app has its own focus-stealing behavior.
**Instead:** SwiftTerm-hosted NSWindow. Direct control over the window lifecycle; Process termination maps directly to vim exit.

---

## Component Build Order

Dependencies run bottom-up. Build in this order:

```
1. PermissionGuard
        ↓ (no deps — pure OS API calls)
2. AppShell (NSStatusItem, NSMenu, LSUIElement setup)
        ↓ (needs PermissionGuard for startup gate)
3. HotkeyMonitor (CGEventTap, double-tap state machine)
        ↓ (needs AppShell to be running)
4. AccessibilityBridge (AXUIElement read + CGEvent paste synthesis + NSPasteboard snapshot)
        ↓ (independent of VimLauncher)
5. TempFileStore (simple file I/O wrapper)
        ↓ (independent)
6. VimLauncher (SwiftTerm NSWindow + Process management)
        ↓ (needs TempFileStore for file path)
7. EditCycleCoordinator (async/await orchestration of 4+5+6)
        ↓ (wires all sub-components)
8. Integration: wire HotkeyMonitor → EditCycleCoordinator.begin()
```

**Rationale:** PermissionGuard must exist before any component that touches AX or Input Monitoring APIs. AppShell is the process entry point and must exist before background threads. HotkeyMonitor can only fire after AppShell's RunLoop is running. The three sub-components (AccessibilityBridge, TempFileStore, VimLauncher) are mutually independent and can be built in parallel. EditCycleCoordinator is last because it integrates all three.

---

## Scalability Considerations

This is a single-user local utility. Scalability concerns are reliability-oriented, not load-oriented.

| Concern | Mitigation |
|---------|------------|
| Re-entrant edit cycles (user double-taps while vim already open) | HotkeyMonitor checks `isEditing` flag in EditCycleCoordinator; ignores trigger if cycle in progress |
| Permission revocation mid-session | PermissionGuard re-checks on each EditCycle begin; surfaces error in menu bar icon state |
| vim exits abnormally (crash, :q!) | Process termination still fires; check if temp file was modified — if not, skip paste to avoid clobbering |
| Target app loses focus during edit | Re-focus target application window before synthesizing Cmd+A/V; use AXUIElement to bring app front |
| Clipboard restore fails | Non-fatal — log warning, do not crash. Original text is preserved in temp file. |

---

## Implications for Phase Build Order

| Phase | Primary Component | Prerequisite |
|-------|-------------------|--------------|
| Phase 1: App Shell | AppShell, PermissionGuard | None |
| Phase 2: Hotkey Detection | HotkeyMonitor | Phase 1 |
| Phase 3: Accessibility + Clipboard | AccessibilityBridge | Phase 1 |
| Phase 4: Vim Launch | TempFileStore, VimLauncher | Phase 1 |
| Phase 5: Edit Cycle Integration | EditCycleCoordinator | Phases 2, 3, 4 |
| Phase 6: Polish + Edge Cases | All components | Phase 5 |

---

## Sources

- CGEventTap usage patterns: [EventTapper (usagimaru)](https://github.com/usagimaru/EventTapper), [alt-tab-macos KeyboardEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/events/KeyboardEvents.swift), [AeroSpace CGEventTap issue](https://github.com/nikitabobko/AeroSpace/issues/1012)
- Global event monitoring approaches: [macOS keyboard event intercepted three ways](https://www.logcg.com/en/archives/2902.html), [SwiftUI global key events guide](https://levelup.gitconnected.com/swiftui-macos-detect-listen-to-global-key-events-two-ways-df19e565793d)
- NSStatusItem / menu bar: [AppCoda menu bar tutorial](https://www.appcoda.com/macos-status-bar-apps/), [polpiella menu-bar-only AppKit guide](https://www.polpiella.dev/a-menu-bar-only-macos-app-using-appkit/)
- AXUIElement patterns: [AXorcist Swift wrapper](https://github.com/steipete/AXorcist), [AXSwift](https://github.com/tmandry/AXSwift), [Apple AXUIElement docs](https://developer.apple.com/documentation/applicationservices/axuielement)
- Permissions: [Accessibility Permission in macOS (jano.dev, 2025)](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html), [macOS privacy permissions guide](https://gannonlawlor.com/posts/macos_privacy_permissions/)
- Process management: [Apple Developer Forums: Child Process](https://developer.apple.com/forums/thread/690310), [NSTask tutorial (Kodeco)](https://www.kodeco.com/1197-nstask-tutorial-for-os-x)
- SwiftTerm (terminal emulator): [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
- NSPasteboard: [Apple NSPasteboard docs](https://developer.apple.com/documentation/appkit/nspasteboard), [Copy string to clipboard in Swift on macOS](https://nilcoalescing.com/blog/CopyStringToClipboardInSwiftOnMacOS/)
- vim-anywhere reference: [cknadler/vim-anywhere](https://github.com/cknadler/vim-anywhere)
