# Phase 4: Vim Session - Research

**Researched:** 2026-04-01
**Domain:** SwiftTerm LocalProcessTerminalView, NSPanel floating window, vim process lifecycle, file mtime exit detection
**Confidence:** HIGH

## Summary

Phase 4 builds `VimSessionManager` — a `@MainActor` class that opens a floating NSPanel containing a SwiftTerm `LocalProcessTerminalView`, starts vim with the captured temp file, and delivers a save/abort result back to the caller via an async callback. The three core technical challenges are: (1) adding SwiftTerm as an SPM dependency and wiring its `LocalProcessTerminalViewDelegate`; (2) creating an NSPanel that floats above other apps but still receives keyboard input for vim; and (3) reliably detecting save vs. abort using file mtime comparison rather than vim scripting.

SwiftTerm's `LocalProcessTerminalView` is the established solution for all PTY requirements. It calls `processDelegate?.processTerminated(source:exitCode:)` when vim exits, provides a `startProcess(executable:args:environment:execName:currentDirectory:)` API, and handles TERM, LANG, and other environment variables by default via `Terminal.getEnvironmentVariables(termName:)`. The panel must override `canBecomeKey` to return `true` — otherwise vim receives no keyboard input — and set `level = .floating` so it stays above other apps. Exit detection via mtime is straightforward using `FileManager.default.attributesOfItem(atPath:)[.modificationDate]` before and after vim exits.

A critical macOS GUI-app pitfall is that the process environment does not include the user's full shell PATH (Homebrew vim at `/opt/homebrew/bin/vim` is invisible to GUI apps). The plan must resolve vim via a login shell subprocess or by reading the shell's expanded PATH explicitly.

**Primary recommendation:** Implement VimSessionManager using LocalProcessTerminalView with NSPanel level=.floating; override canBecomeKey=true; detect exit outcome by mtime; resolve vim binary via `/bin/zsh -l -c "which vim"` to respect the user's PATH.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Window opens centered on the active display.
- **D-02:** Window size remembered across sessions via UserDefaults. Sensible default (80x24 or 100x30) on first launch.
- **D-03:** NSPanel with `.floating` window level stays above other windows. Clicking another app does not hide or defocus the vim window.
- **D-04:** Standard minimal NSPanel title bar with "AnyVim" or the filename. Drag handle and close button.
- **D-05:** Check temp file mtime before launching vim. After vim's process terminates, compare mtime. Changed = :wq (save), unchanged = :q! (abort).
- **D-06:** Vim process crash or kill (kill -9) → treat as abort.
- **D-07:** Red close button (X) kills vim process and treats it as abort.
- **D-08:** Search PATH to find vim via `/usr/bin/env vim` or resolving $PATH. Homebrew vim preferred over system vim.
- **D-09:** Vim not found in PATH → show macOS alert, suggest Homebrew, treat as abort.
- **D-10:** `NSFont.monospacedSystemFont` (SF Mono), default size 13-14pt.
- **D-11:** Terminal colors match system appearance — light/dark background. Vim colorscheme renders on top.
- **D-12:** Standard NSPanel, no special effects. Padding around the SwiftTerm view.

### Claude's Discretion
- SwiftTerm `LocalProcessTerminalView` configuration details and PTY setup
- How to detect process termination (SwiftTerm delegate vs Process.waitUntilExit vs DispatchSource)
- Default window dimensions (exact character columns/rows)
- Environment variables passed to the vim subprocess (TERM, SHELL, etc.)
- Protocol abstraction design for VimSessionManager (following established patterns)
- How VimSessionManager communicates exit status back to the caller (closure, async/await)
- Font size within the 13-14pt range
- Exact padding values around the terminal view

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VIM-01 | App opens a lightweight dedicated terminal window (not Terminal.app) with vim loaded with the temp file | SwiftTerm LocalProcessTerminalView + NSPanel is the verified approach; no Terminal.app involved |
| VIM-02 | Terminal window uses SwiftTerm or equivalent for a PTY-backed vim session | LocalProcessTerminalView internally uses forkpty; no manual PTY wiring needed |
| VIM-03 | User's existing ~/.vimrc is used (vim launched normally) | Launching vim binary directly with file arg respects ~/.vimrc automatically; no flags that suppress it |
| VIM-04 | App detects vim process termination (user did :wq or :q!) | `processTerminated(source:exitCode:)` delegate + mtime comparison gives save/abort signal |
</phase_requirements>

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftTerm | 1.13.0 (March 2026) | PTY-backed terminal view hosting vim | Only maintained Swift library for embedded terminal with PTY. Used in commercial SSH clients. `LocalProcessTerminalView` handles PTY, process launch, and keyboard/mouse events without additional wiring. |
| AppKit — NSPanel | macOS 13+ SDK | Floating window container | NSPanel subclass of NSWindow; `level = .floating` keeps it above all apps. Supports `canBecomeKey` override so vim receives keyboard input. |
| Foundation — FileManager | macOS 13+ SDK | File mtime comparison for exit detection | `attributesOfItem(atPath:)[.modificationDate]` reads mtime before and after vim exits. Standard, no dependencies. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UserDefaults | Built-in | Persist window size across sessions (D-02) | Store last-used NSRect / (columns, rows) under a fixed key |
| ProcessInfo | Built-in | Access GUI app's limited PATH | Use as fallback; prefer login shell resolution for Homebrew vim |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mtime comparison | Pass `-c "au VimLeave * call writefile(['saved'], '/tmp/flag')"` | Vim scripting approach — fragile, overrides user vimrc interaction, two processes |
| mtime comparison | Watch exit code (vim exits 0 for both :wq and :q!) | Exit code is 0 for both — not useful for distinguishing save vs abort |
| Login shell PATH resolution | Hardcode `/usr/bin/vim` fallback | System vim is always present but ignores Homebrew vim per D-08 requirement |
| NSPanel subclass | Raw NSWindow with level override | NSPanel is the semantic macOS type for auxiliary floating windows; NSWindow level works identically but NSPanel is conventional |

**Installation (Xcode SPM):**
SwiftTerm must be added through Xcode's package manager UI:
```
File → Add Package Dependencies → https://github.com/migueldeicaza/SwiftTerm
Select version: 1.13.0 (Up to Next Major)
Add to target: AnyVim
```
This cannot be done via CLI — requires Xcode GUI (or direct project.pbxproj edit).

**Version verification:** SwiftTerm 1.13.0 released March 27, 2026 — confirmed from GitHub releases. This is the version specified in CLAUDE.md. No Package.swift exists in this project (Xcode-native project, not SPM-managed).

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/AnyVim/
├── VimSessionManager.swift    # @MainActor class — owns NSPanel, LocalProcessTerminalView
├── VimPanel.swift             # NSPanel subclass — canBecomeKey, canBecomeMain overrides
├── SystemProtocols.swift      # Add VimLaunching protocol here (established pattern)
└── (existing files unchanged)
```

### Pattern 1: Manager Class with Async/Await Continuation

**What:** VimSessionManager exposes an `async func openVimSession(with captureResult: CaptureResult) async -> VimExitResult` method that suspends via a `CheckedContinuation` until vim exits. The continuation is stored as an instance variable and resumed inside `processTerminated`.

**When to use:** The caller (`AppDelegate.handleHotkeyTrigger`) is already in an async `Task { @MainActor in ... }` context, making async/await the cleanest integration point.

**Example:**
```swift
// Source: established pattern from HotkeyManager.onTrigger closure pattern (Phase 2)
// adapted to async/await for Phase 4
@MainActor
final class VimSessionManager {
    private var continuation: CheckedContinuation<VimExitResult, Never>?

    func openVimSession(with captureResult: CaptureResult) async -> VimExitResult {
        // record mtime before launching
        let mtimeBefore = modificationDate(of: captureResult.tempFileURL)
        // create and show NSPanel with LocalProcessTerminalView
        // ...
        return await withCheckedContinuation { cont in
            self.continuation = cont
            // start vim process
        }
    }

    // Called by LocalProcessTerminalViewDelegate
    private func handleProcessTerminated(exitCode: Int32?) {
        let mtimeAfter = modificationDate(of: currentTempFileURL)
        let result: VimExitResult = (mtimeAfter != mtimeBefore) ? .saved : .aborted
        continuation?.resume(returning: result)
        continuation = nil
    }
}

enum VimExitResult {
    case saved
    case aborted
}
```

### Pattern 2: VimPanel NSPanel Subclass

**What:** A small NSPanel subclass that overrides `canBecomeKey` and `canBecomeMain` to return `true`. Without this override, vim receives no keyboard input even when the window is frontmost.

**When to use:** Always — `NSPanel` defaults for `canBecomeKey` are context-sensitive and unreliable for a terminal hosting vim.

**Example:**
```swift
// Source: standard NSPanel override, verified from Apple docs + community examples
final class VimPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

**NSPanel construction:**
```swift
let panel = VimPanel(
    contentRect: centeredRect,
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false
)
panel.level = .floating
panel.title = "AnyVim"
panel.isReleasedWhenClosed = false  // ARC manages lifetime via VimSessionManager
```

Note: Do NOT use `.nonactivatingPanel` in the style mask. That mask prevents keyboard focus. The vim window needs to become key.

### Pattern 3: SwiftTerm LocalProcessTerminalView Delegate Wiring

**What:** `LocalProcessTerminalView` has a separate `processDelegate` property (type `LocalProcessTerminalViewDelegate?`) distinct from `terminalDelegate`. The `processDelegate` gets `processTerminated(source:exitCode:)`. VimSessionManager implements this protocol.

**When to use:** Always with LocalProcessTerminalView — this is the only supported termination signal.

**Example:**
```swift
// Source: SwiftTerm MacLocalTerminalView.swift (verified via WebFetch)
// LocalProcessTerminalViewDelegate protocol:
func processTerminated(source: TerminalView, exitCode: Int32?) {
    // exitCode is Int32? — nil means I/O error, 0 is normal vim exit (both :wq and :q!)
    // Use mtime comparison here, NOT exitCode, to distinguish save from abort
    handleProcessTerminated()
}
```

### Pattern 4: Login-Shell PATH Resolution for Vim Binary

**What:** Run `/bin/zsh -l -c "which vim"` via `Process` to resolve vim in the user's full shell environment, including Homebrew paths. This is the only reliable way to find Homebrew vim from a GUI app.

**When to use:** Once at VimSessionManager initialization or before first launch.

**Example:**
```swift
// Source: macOS GUI app PATH pattern — verified from Apple Developer Forums
func resolveVimPath() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", "which vim"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()  // discard stderr
    try? process.run()
    process.waitUntilExit()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: output, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (path?.isEmpty == false) ? path : nil
}
```

### Pattern 5: Mtime-Based Exit Detection

**What:** Read `FileAttributeKey.modificationDate` before launching vim, then read it again after `processTerminated` fires. If they differ, user saved (:wq). If same, user aborted (:q!) or quit without changes.

**When to use:** Always — this is decision D-05.

**Example:**
```swift
// Source: Apple Developer Documentation — FileManager.attributesOfItem
func modificationDate(of url: URL) -> Date? {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attrs?[.modificationDate] as? Date
}
```

### Pattern 6: Centering on Active Display (D-01)

**What:** Use `NSScreen.main` to get the screen with the current keyboard focus, then center the window rect on it.

**When to use:** On every session open — display may change between invocations.

**Example:**
```swift
// Source: AppKit NSScreen documentation
func centeredRect(columns: Int, rows: Int, font: NSFont) -> NSRect {
    let charSize = font.boundingRectForFont
    let width = CGFloat(columns) * charSize.width + 2 * padding
    let height = CGFloat(rows) * charSize.height + 2 * padding + titleBarHeight
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let screenRect = screen.visibleFrame
    let x = screenRect.midX - width / 2
    let y = screenRect.midY - height / 2
    return NSRect(x: x, y: y, width: width, height: height)
}
```

### Pattern 7: Window Size Persistence (D-02)

**What:** Save the NSPanel frame to UserDefaults on window resize (observe `NSWindow.didResizeNotification`). Restore on next open.

**When to use:** Always — user resizes should persist per D-02.

**Example:**
```swift
// Key: "VimWindowFrame"
// Save: UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "VimWindowFrame")
// Restore: if let str = UserDefaults.standard.string(forKey: "VimWindowFrame") {
//   panel.setFrame(NSRectFromString(str), display: false) }
```

### Pattern 8: Starting vim with startProcess

**What:** The exact `startProcess` call that passes vim binary path, file argument, and default environment (including TERM=xterm-256color, HOME, USER, LANG).

**When to use:** After the panel and terminal view are set up.

**Example:**
```swift
// Source: SwiftTerm LocalProcess.swift — environment defaults to Terminal.getEnvironmentVariables
// when nil is passed (sets TERM=xterm-256color, HOME, USER, LANG, etc.)
terminalView.startProcess(
    executable: vimPath,        // resolved via login shell "which vim"
    args: [fileURL.path],       // the temp file
    environment: nil,           // let SwiftTerm provide sensible defaults
    execName: nil,
    currentDirectory: nil
)
```

Note: Passing `nil` for `environment` lets SwiftTerm call `Terminal.getEnvironmentVariables(termName: "xterm-256color")` which sets TERM, HOME, USER, LANG, LOGNAME, LC_TYPE, DISPLAY, COLORTERM. This is sufficient for vim. Do NOT suppress this by passing an empty array.

### Anti-Patterns to Avoid

- **Using `.nonactivatingPanel` style mask:** Prevents vim from receiving keyboard input even when `canBecomeKey` returns true. This mask is for hotkey/launcher panels that do not need keyboard focus. The vim terminal needs to be the key window.
- **Using exit code to detect save vs abort:** Vim exits 0 for both `:wq` and `:q!`. Exit code is only useful for detecting crashes (non-zero). Use mtime instead.
- **Accessing `localizedName` without nil check:** `NSRunningApplication.localizedName` is Optional. Already handled in prior phases.
- **Storing `LocalProcessTerminalView` as a local variable:** Must be retained as an instance property on VimSessionManager — same ARC pattern as NSStatusItem in Phase 1.
- **Calling `panel.makeKeyAndOrderFront(nil)` before `terminalView` is added to view hierarchy:** Can cause the terminal to not render on first open.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PTY management | Manual forkpty + file descriptor wiring | `LocalProcessTerminalView` | PTY is complex (SIGWINCH, resize, raw mode, signals). SwiftTerm handles all of it. |
| Terminal emulation | Custom ANSI/VT100 parser for vim output | `LocalProcessTerminalView` | VT100 emulation has hundreds of escape sequences. vim uses many of them (cursor movement, reverse video, colors). Incomplete implementation causes garbled display. |
| Process termination monitoring | `DispatchSource.makeProcessSource` manually | `LocalProcessTerminalView` + processDelegate | SwiftTerm already wires `DispatchSource.makeProcessSource(.exit)` internally and calls `waitpid`. Duplicating this causes double-wait. |
| PATH expansion in GUI context | Parsing shell rc files | `/bin/zsh -l -c "which vim"` subprocess | Shell config files (`.zshrc`, `.zprofile`, `.zshenv`) have complex conditional logic. Only a login shell can interpret them correctly. |

**Key insight:** SwiftTerm eliminates the entire PTY/terminal emulation surface area. The only custom logic needed is window management, vim resolution, and mtime comparison.

---

## Common Pitfalls

### Pitfall 1: NSPanel Without canBecomeKey Override
**What goes wrong:** vim opens but no keystrokes are delivered. The terminal appears but is completely unresponsive.
**Why it happens:** `NSPanel` has context-sensitive default behavior for `canBecomeKey`. Without an explicit `return true` override, panels at `.floating` level may not accept keyboard events.
**How to avoid:** Always subclass NSPanel and override `canBecomeKey { return true }` and `canBecomeMain { return true }`.
**Warning signs:** Can type in other apps but not in the vim panel; vim cursor does not blink.

### Pitfall 2: Using `.nonactivatingPanel` Style Mask
**What goes wrong:** Despite `canBecomeKey = true`, vim receives no input.
**Why it happens:** `.nonactivatingPanel` explicitly prevents the panel from becoming the key window, overriding the `canBecomeKey` property.
**How to avoid:** Use `[.titled, .closable, .resizable]` style masks. Do not add `.nonactivatingPanel`.
**Warning signs:** Same symptoms as Pitfall 1.

### Pitfall 3: GUI App PATH Missing Homebrew Paths
**What goes wrong:** `which vim` in a Process launched from AnyVim finds `/usr/bin/vim` even when the user has Homebrew vim at `/opt/homebrew/bin/vim`. Per D-08, Homebrew vim should be preferred.
**Why it happens:** macOS GUI apps are launched by launchd, not by the user's shell, so they inherit a minimal PATH that does not include shell initialization from `.zshrc`/`.zprofile`.
**How to avoid:** Run `/bin/zsh -l -c "which vim"` to use a login shell that loads the user's full PATH. The `-l` flag triggers login shell initialization.
**Warning signs:** Users with Homebrew vim complain their Homebrew-configured `~/.vimrc` (or plugins) are not available.

### Pitfall 4: Exit Code Cannot Distinguish Save From Abort
**What goes wrong:** Treating exit code 0 as "saved" marks every vim exit as a save, including `:q!`.
**Why it happens:** Vim exits 0 for normal exit regardless of whether the file was written. Only crashes or explicit error exits produce non-zero codes.
**How to avoid:** Use mtime comparison per D-05. Record `modificationDate` before `startProcess`, compare after `processTerminated`.
**Warning signs:** Aborted edits paste back original content or overwrite text fields.

### Pitfall 5: SwiftTerm processDelegate vs terminalDelegate Confusion
**What goes wrong:** Implementing `TerminalViewDelegate` and waiting for `processTerminated` but the method is never called because it belongs to `LocalProcessTerminalViewDelegate`, which must be set on `terminalView.processDelegate`, not `terminalView.terminalDelegate`.
**Why it happens:** `LocalProcessTerminalView` has two delegates: `terminalDelegate` (for scroll, title, bell, link events) and `processDelegate` (for process lifecycle). They are different protocols assigned to different properties.
**How to avoid:** Set `terminalView.processDelegate = self` (not `terminalView.terminalDelegate = self`) when listening for termination.
**Warning signs:** `processTerminated` method exists and compiles but is never called.

### Pitfall 6: isReleasedWhenClosed Causes Crash on Reopen
**What goes wrong:** Closing the vim panel and reopening for a second vim session crashes with EXC_BAD_ACCESS.
**Why it happens:** `NSWindow.isReleasedWhenClosed` defaults to `true` for NSPanel, which causes AppKit to release the panel when it's closed. The VimSessionManager's retained reference becomes a dangling pointer.
**How to avoid:** Set `panel.isReleasedWhenClosed = false`. VimSessionManager owns the lifecycle.
**Warning signs:** Only crashes on second invocation; first session works fine.

### Pitfall 7: LocalProcessTerminalView Frame Not Set Before startProcess
**What goes wrong:** Terminal renders at zero size or vim cannot determine terminal dimensions, leading to garbled layout.
**Why it happens:** `LocalProcessTerminalView.getWindowSize()` derives `ws_row`/`ws_col` from the view's `frame`. If the view has a zero frame when the process starts, vim sees a 0x0 terminal.
**How to avoid:** Set the terminal view's frame (and add it to the window's content view) before calling `startProcess`.
**Warning signs:** vim opens but all content appears on one line; resize fixes it.

---

## Code Examples

Verified patterns from official sources and SwiftTerm source inspection:

### LocalProcessTerminalViewDelegate Protocol
```swift
// Source: SwiftTerm MacLocalTerminalView.swift — verified via WebFetch
protocol LocalProcessTerminalViewDelegate: AnyObject {
    func processTerminated(source: TerminalView, exitCode: Int32?)
    // Additional optional methods exist but processTerminated is the critical one
}
```

### Setting Font (D-10)
```swift
// Source: SwiftTerm ViewController.swift sample app
terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
```

### Color Configuration for Dark/Light Mode (D-11)
```swift
// Source: SwiftTerm MacTerminalView.swift — nativeForegroundColor / nativeBackgroundColor
// configureNativeColors() sets system defaults:
terminalView.configureNativeColors()
// OR manually per appearance:
if NSApp.effectiveAppearance.name == .darkAqua {
    terminalView.nativeBackgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
    terminalView.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
} else {
    terminalView.nativeBackgroundColor = .white
    terminalView.nativeForegroundColor = .black
}
```

### File Modification Date Read
```swift
// Source: Apple Developer Documentation — FileManager.attributesOfItem(atPath:)
func modificationDate(of url: URL) -> Date? {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attrs?[FileAttributeKey.modificationDate] as? Date
}
```

### NSPanel Lifecycle (complete minimal pattern)
```swift
// Source: NSPanel Apple docs + community pattern verification
final class VimPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// In VimSessionManager:
let panel = VimPanel(
    contentRect: centeredRect,
    styleMask: [.titled, .closable, .resizable],
    backing: .buffered,
    defer: false
)
panel.level = .floating
panel.isReleasedWhenClosed = false
panel.title = "AnyVim"
```

### UserDefaults Window Frame Persistence (D-02)
```swift
// Source: AppKit NSWindow documentation
private let windowFrameKey = "VimWindowFrame"

func saveWindowSize(_ panel: NSPanel) {
    UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: windowFrameKey)
}

func restoreWindowSize(_ panel: NSPanel) {
    if let str = UserDefaults.standard.string(forKey: windowFrameKey) {
        panel.setFrame(NSRectFromString(str), display: false)
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Launch Terminal.app via NSWorkspace | SwiftTerm LocalProcessTerminalView | 2019+ | Full lifecycle control, no external app dependency |
| MacVim as vim host | CLI vim in SwiftTerm PTY | 2020+ | No MacVim installation required, users' ~/.vimrc works |
| Manual PTY with NSTask/Process | LocalProcessTerminalView | SwiftTerm v1.0+ | PTY plumbing, signal handling, resize handled internally |
| SwiftUI MenuBarExtra | AppKit NSStatusItem | macOS 12 regression | NSStatusItem is stable; MenuBarExtra has timing/dismiss issues |

**Deprecated/outdated:**
- `Foundation.Process` (NSTask) for vim: vim requires a PTY; Process does not provide one. SwiftTerm handles PTY setup internally.
- AXSwift: unmaintained since 2021 — not needed for Phase 4.

---

## Open Questions

1. **Swift 6 strict concurrency and LocalProcessTerminalViewDelegate**
   - What we know: LocalProcessTerminalView's `processDelegate` is a weak reference. The processTerminated callback fires from a DispatchSource handler (internal to SwiftTerm), which may not be `@MainActor`.
   - What's unclear: Whether SwiftTerm dispatches processTerminated to the main queue or a background queue in v1.13.0.
   - Recommendation: Wrap the callback body in `Task { @MainActor in ... }` to ensure safe CheckedContinuation resumption. Verify during implementation; add `MainActor.assumeIsolated` or `DispatchQueue.main.async` if needed.

2. **SPM dependency addition to Xcode project**
   - What we know: The project has no existing SPM dependencies. SwiftTerm must be added through Xcode UI (File → Add Package Dependencies).
   - What's unclear: Whether the Xcode project requires any entitlement changes for SwiftTerm (sandbox is already disabled per prior phases).
   - Recommendation: Plan Wave 0 as: add SwiftTerm via Xcode, verify build succeeds, then proceed to implementation.

3. **Default terminal size in character units**
   - What we know: D-02 specifies 80x24 or 100x30 as sensible defaults. CLAUDE.md does not specify exact value.
   - What's unclear: Which default feels most appropriate for vim editing.
   - Recommendation: Use 100 columns x 35 rows as the default (wider than 80x24, more comfortable for prose editing). Store and restore from UserDefaults.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| vim | VIM-01, VIM-03 | ✓ | 9.1.1752 (macOS system) | Show alert per D-09 |
| Homebrew vim | D-08 (preferred) | ✗ | — | Fall back to /usr/bin/vim |
| SwiftTerm (SPM) | VIM-02 | ✗ (not yet added) | 1.13.0 available | Must add in Wave 0 |
| Xcode | Build | ✓ | 26.4 | — |
| Swift | Build | ✓ | 6.3 | — |
| zsh | PATH resolution | ✓ | Built-in macOS | /bin/bash fallback |

**Missing dependencies with no fallback:**
- SwiftTerm: not yet in the Xcode project. Must be added via Xcode "Add Package Dependencies" as the first Wave 0 task. Blocks all other tasks.

**Missing dependencies with fallback:**
- Homebrew vim: system `/usr/bin/vim` is available as fallback. Login shell resolution will find it automatically if Homebrew vim is not installed.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built into Xcode) |
| Config file | AnyVim.xcodeproj (test target: AnyVimTests) |
| Quick run command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| Full suite command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VIM-01 | VimSessionManager.openVimSession returns without error given a valid temp file URL | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ Wave 0 |
| VIM-02 | LocalProcessTerminalView is created with a non-nil process after startProcess | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ Wave 0 |
| VIM-03 | startProcess is called with the vim binary path and the temp file path as argument | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ Wave 0 |
| VIM-04 | Mtime comparison returns .saved when file is modified, .aborted when unchanged | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ Wave 0 |
| D-05 | modificationDate(of:) returns nil for non-existent file | unit | same | ❌ Wave 0 |
| D-08 | resolveVimPath() returns a non-nil path containing "vim" | unit | same | ❌ Wave 0 |
| D-09 | openVimSession shows alert and returns .aborted when vim is not found | unit (mock) | same | ❌ Wave 0 |

Note: The window display aspects (VIM-01 visual confirmation, keyboard input) are manual-only. Unit tests cover the protocol surface and logic paths.

### Sampling Rate
- **Per task commit:** `xcodebuild test -project /Users/nick/Projects/any-vim/AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `AnyVimTests/VimSessionManagerTests.swift` — covers VIM-01 through VIM-04, D-05, D-08, D-09
- [ ] Add SwiftTerm SPM package to AnyVim.xcodeproj — required before any VimSessionManager code compiles

---

## Project Constraints (from CLAUDE.md)

- **Language:** Swift 6 with SWIFT_STRICT_CONCURRENCY=complete. All new code must be @MainActor-isolated or explicitly actor-safe.
- **NSStatusItem:** Already retained — do not change existing AppDelegate patterns.
- **CGEventTap:** Not relevant to Phase 4 but health check pattern still runs.
- **SwiftTerm 1.13.0:** Specified version — use exactly this version.
- **NSPanel not SwiftUI MenuBarExtra:** Menu bar is already NSStatusItem; Phase 4 uses NSPanel for the vim window, not SwiftUI.
- **Raw AXUIElement not AXSwift:** Not relevant to Phase 4.
- **No Dock icon:** `NSApp.setActivationPolicy(.accessory)` set in Phase 1 — opening the vim panel should NOT change activation policy.
- **Manager ownership pattern:** VimSessionManager must be an instance property of AppDelegate.
- **Sandbox disabled:** Required for SwiftTerm/vim to access user's filesystem. This should already be configured from Phase 1 (CGEventTap requires it).

---

## Sources

### Primary (HIGH confidence)
- SwiftTerm GitHub (migueldeicaza/SwiftTerm v1.13.0, March 2026) — LocalProcessTerminalView API, delegate patterns, processTerminated signature, startProcess parameters, default environment variables, font configuration
- SwiftTerm MacLocalTerminalView.swift (WebFetch of source) — `processDelegate` property type, exact `processTerminated(source:exitCode:)` signature, `LocalProcessTerminalViewDelegate` protocol
- SwiftTerm ViewController.swift sample (WebFetch) — `font = NSFont.monospacedSystemFont(ofSize:weight:)` pattern, `processTerminated` closing the window
- SwiftTerm LocalProcess.swift (WebFetch) — `DispatchSource.makeProcessSource(.exit)` internals, `waitpid` exit code, `Terminal.getEnvironmentVariables(termName:)` default environment
- Apple Developer Documentation — `FileManager.attributesOfItem(atPath:)`, `FileAttributeKey.modificationDate`, `NSPanel`, `NSWindow.level`, `NSWindow.isReleasedWhenClosed`
- CLAUDE.md — SwiftTerm 1.13.0 locked, NSPanel floating window pattern, NSFont.monospacedSystemFont requirement

### Secondary (MEDIUM confidence)
- FloatingPanel NSPanel gist (jordibruin) — canBecomeKey/canBecomeMain override pattern confirmed in multiple community sources
- Apple Developer Forums thread 74371 — GUI app PATH not inheriting user shell config
- WebSearch: SwiftTerm default environment sets TERM=xterm-256color via Terminal.getEnvironmentVariables — mentioned in SwiftTerm README (not directly inspected)

### Tertiary (LOW confidence)
- Community NSPanel examples (2021-2024) — `.nonactivatingPanel` avoidance for keyboard-input panels (multiple sources agree)
- macOS GUI PATH resolution pattern `/bin/zsh -l -c "which vim"` — community pattern, not official Apple recommendation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — SwiftTerm v1.13.0 is the locked decision in CLAUDE.md; API verified from source
- Architecture: HIGH — Delegate signature and patterns verified from SwiftTerm source files
- Pitfalls: HIGH for NSPanel/canBecomeKey and exit code issues (multiple verified sources); MEDIUM for Swift 6 concurrency dispatch behavior (implementation detail not directly verified)
- Environment availability: HIGH — vim and toolchain verified via bash

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (SwiftTerm is actively maintained; API stable in 1.x series)
