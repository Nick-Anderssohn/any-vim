# Domain Pitfalls

**Domain:** macOS system-wide keyboard utility / vim-anywhere type tool
**Researched:** 2026-03-31

---

## Critical Pitfalls

Mistakes that cause rewrites or major reliability failures.

---

### Pitfall 1: The Silent Event Tap

**What goes wrong:** `CGEvent.tapCreate` returns a non-nil tap and `tapIsEnabled()` returns `true`, but no keyboard events are ever received. The tap appears healthy but is functionally dead.

**Why it happens:** macOS TCC (Transparency, Consent, and Control) evaluates app identity at launch via code signature. If the binary has been re-signed (e.g., after a local rebuild without a Developer ID certificate), or if it is launched via Finder/Dock rather than the CLI, macOS may silently revoke or refuse to activate the event tap. The "disabled by timeout" callback path does not reliably fire in this case — the tap simply receives nothing.

**Consequences:** The global hotkey never fires. The app appears to run normally. Users (and developers) see no error.

**Prevention:**
- Implement a periodic health monitor: `Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true)` that calls `CGEvent.tapIsEnabled(tap:)` and re-installs the tap if it returns false.
- In the callback, explicitly handle `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput` by calling `CGEvent.tapEnable(tap:, enable: true)`.
- During development, sign with a Developer ID certificate as early as possible — unsigned or ad-hoc signed builds are most prone to this.
- Call `CGPreflightListenEventAccess()` on startup; do not proceed to install the tap if it returns false.

**Warning signs:**
- Tap installs without error but hotkey never fires.
- Problem appears/disappears depending on whether the app was launched from Terminal vs. Finder.
- Problem only manifests after a rebuild.

**Phase:** Foundation / event monitoring phase.

---

### Pitfall 2: Permission State Not Polled After Grant

**What goes wrong:** The app prompts the user for Accessibility or Input Monitoring permission. The user grants it in System Settings. The app continues to fail because it checked permissions once at launch and cached the result — it does not re-check after the user grants access.

**Why it happens:** `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` return the state at the moment of the call. Most implementations check at startup and either proceed or bail. If the user grants permission mid-session, the app must be restarted or must re-poll.

**Consequences:** Users grant permission in System Settings, return to the app, and find it still does not work. Common support complaint in the original vim-anywhere project.

**Prevention:**
- After displaying the permission prompt, poll `AXIsProcessTrusted()` on a timer (e.g., every 2 seconds) until it becomes true, then proceed to install the event tap and begin normal operation without requiring a full app restart.
- Show a clear status indicator in the menu bar (e.g., a badge or different icon) while permissions are missing.

**Warning signs:**
- App works only after a full quit-and-relaunch following permission grant.
- Users report "it didn't work" immediately after granting permissions.

**Phase:** Foundation / permissions phase.

---

### Pitfall 3: Clipboard Clobber — User Loses In-Flight Copy

**What goes wrong:** The grab-edit-paste cycle uses `Cmd+C` and `Cmd+V` to move text through the system clipboard. This unconditionally overwrites whatever the user had copied previously. If anything interrupts the cycle (vim crashed, user pressed Escape instead of :wq, terminal closed), the user's original clipboard is gone.

**Why it happens:** NSPasteboard holds exactly one set of content at a time. Writing new content — even programmatically — destroys the previous content immediately. The original vim-anywhere project has a long-standing open issue about this (issue #61).

**Consequences:** Users lose clipboard contents they were relying on. The edit cycle feels unsafe and unreliable for multi-step workflows.

**Prevention:**
- Save the full pasteboard contents before the grab step using `NSPasteboard.general.pasteboardItems` (captures all types, not just plain text).
- Restore unconditionally: on vim exit (normal or abnormal), on timeout, on any error path.
- Be aware that non-text pasteboard items (images, files, rich text) require restoring each item's full set of types — not just `NSPasteboardTypeString`.
- Use `NSPasteboard.general.changeCount` to detect if the user has copied something new during the vim session; if changeCount changed after the paste step, do not overwrite.

**Warning signs:**
- Users report "it ate my clipboard."
- Text is correctly pasted back but the previous clipboard is gone.

**Phase:** Core edit cycle phase. Must be addressed before the feature is considered functional.

---

### Pitfall 4: Timing Races Between Simulated Keystrokes

**What goes wrong:** The app simulates `Cmd+A` then `Cmd+C` to grab text, or `Cmd+A` then `Cmd+V` to paste text back. The target application has not finished processing the first event before the second arrives. Result: partial selection, paste into wrong position, or no-op.

**Why it happens:** `CGEvent.post` returns immediately — it does not wait for the target app to process the event. Applications with complex text handling (Electron apps, browsers, web text editors) are particularly slow to update their internal state after a selection event.

**Consequences:** Grab produces empty clipboard (Cmd+C fired before Cmd+A completed). Paste overwrites partial text or inserts in wrong position.

**Prevention:**
- Insert explicit delays between simulated events. 100ms between keystrokes is a commonly reported working threshold. For Cmd+A → Cmd+C, use at least 150ms.
- After Cmd+C, wait before reading the pasteboard — the clipboard is populated asynchronously. Poll `NSPasteboard.general.changeCount` to confirm the copy actually happened rather than assuming it after a fixed delay.
- After returning focus to the target app (via `NSRunningApplication.activate`), wait before simulating paste. A 200-500ms delay covers most apps; make this configurable internally.

**Warning signs:**
- Works reliably in simple apps (TextEdit, Notes) but fails in browsers or Electron apps.
- Captured text is sometimes empty.
- Pasted text appears at the cursor position rather than replacing the selection.

**Phase:** Core edit cycle phase.

---

### Pitfall 5: Electron and Web App Text Field Incompatibility

**What goes wrong:** `Cmd+A` / `Cmd+C` / `Cmd+V` via simulated CGEvents do not reliably interact with text fields in Electron apps, Chrome, or complex web applications.

**Why it happens:** Electron apps expose a non-standard or incomplete accessibility tree. Known bugs include incorrect character range selection when lines begin with whitespace. Some web-based text editors (CodeMirror, Monaco, ProseMirror) manage their own virtual DOM and may not respond to `Cmd+A` in the expected way — they may select only within a focused paragraph rather than the whole field.

**Consequences:** The tool silently grabs partial text (user edits only part of their content), or pastes back into the wrong location.

**Prevention:**
- Accept this as a known limitation for v1 and document it explicitly.
- Consider using `AXUIElementCopyAttributeValue` with `kAXValueAttribute` / `kAXSelectedTextAttribute` as a more reliable path for apps that expose a proper accessibility tree, falling back to Cmd+A/Cmd+C when the attribute is unavailable.
- Test against: VSCode (Electron), Slack (Electron), Chrome, Firefox, Safari, and native AppKit text fields as the baseline matrix.

**Warning signs:**
- Captured text is truncated or contains only a paragraph of a multi-paragraph field.
- Paste succeeds but text appears in the wrong location (cursor position rather than replacing selection).

**Phase:** Core edit cycle phase (testing sub-task).

---

## Moderate Pitfalls

---

### Pitfall 6: Double-Tap Detection Triggering During Normal Typing

**What goes wrong:** The double-tap Control trigger fires unexpectedly during normal keyboard use — for example, when using terminal shortcuts like `Ctrl+C` or `Ctrl+Z`, or when pressing Control rapidly as part of a keyboard shortcut.

**Why it happens:** Detecting a "double-tap of a modifier-only key" requires distinguishing between: (a) Control pressed twice quickly with no other key in between, and (b) Control pressed as part of a key combination. The CGEvent stream for modifier keys uses `flagsChanged` events, not `keyDown` events, making state tracking non-trivial. A naive timestamp comparison will produce false positives.

**Consequences:** Vim opens unexpectedly in the middle of a terminal or editor session.

**Prevention:**
- Track the full modifier key state machine: a valid double-tap must be two `flagsChanged` events where Control goes from absent to present, then present to absent (key-up), then absent to present again — with no intervening `keyDown` events in between each cycle.
- Set a debounce window (250-350ms is a good target) — two taps further apart than this are not a double-tap, two taps closer than ~50ms are likely a hardware bounce.
- Mask out taps that occur while any other modifier (Cmd, Option, Shift) is simultaneously held.

**Warning signs:**
- Vim opens when the user types `Ctrl+C` in a terminal.
- Vim opens occasionally during fast typing.

**Phase:** Foundation / event monitoring phase.

---

### Pitfall 7: Focus Not Returned to Original App After Vim Exit

**What goes wrong:** After `:wq` in vim, the paste step requires the original application to be frontmost. If focus is not explicitly restored, the paste goes to the wrong window or nowhere.

**Why it happens:** Launching a terminal window for vim steals focus. When the terminal window closes, macOS does not automatically return focus to the previously active application — it uses its own focus-return heuristic that may pick the wrong window.

**Consequences:** The paste is delivered to the wrong application, or the original text field is no longer focused when Cmd+V fires.

**Prevention:**
- Capture `NSWorkspace.shared.frontmostApplication` at trigger time (before launching vim), not at paste time.
- After vim exits and the terminal window closes, explicitly call `previousApp.activate(options: .activateIgnoringOtherApps)` before simulating the paste.
- Add a delay (100-200ms) after `activate()` before posting paste events — the window focus transition is asynchronous.

**Warning signs:**
- Paste goes to the wrong window.
- Paste appears to succeed but nothing changes in the original field.
- Problem is intermittent — depends on how fast the user switches away from the terminal.

**Phase:** Core edit cycle phase.

---

### Pitfall 8: NSStatusItem Released and Menu Bar Icon Disappears

**What goes wrong:** The menu bar status item (the icon in the top-right corner) vanishes shortly after the app launches.

**Why it happens:** `NSStatusBar.system.statusItem(withLength:)` returns an object that is only retained as long as a strong reference exists. If stored in a local variable in `applicationDidFinishLaunching`, it is released when that method returns.

**Prevention:**
- Store `NSStatusItem` as a `let` property on the `AppDelegate` (or a long-lived owner object), not as a local variable.
- Verify the icon persists across multiple app activations during the first build.

**Warning signs:**
- Menu bar icon appears for a moment then disappears.
- Icon disappears after the first hotkey trigger.

**Phase:** Foundation / menu bar setup phase.

---

### Pitfall 9: TCC Permission Reset on Rebuild Without Developer ID

**What goes wrong:** During development, each Xcode build re-signs the binary with an ad-hoc signature. macOS TCC treats the re-signed binary as a new application and revokes the previously granted Accessibility permission. The developer must re-grant permission after every build.

**Why it happens:** TCC ties permissions to the app's code signature. An ad-hoc signature changes per build. A Developer ID signature is stable across builds.

**Consequences:** Extremely slow development iteration. Easy to mistake a permission issue for a code bug.

**Prevention:**
- Obtain a free Apple Developer account and sign builds with a Developer ID as early as Phase 1. This is free and does not require App Store submission.
- Document the `tccutil reset Accessibility com.yourapp.bundleid` command for the development workflow until signing is set up.
- Use a consistent, unique bundle identifier from day one — changing it later resets all TCC grants.

**Warning signs:**
- The app works on first launch but breaks after rebuilding.
- Granting Accessibility permission in System Settings does not persist across rebuilds.

**Phase:** Foundation phase. Address bundle ID and signing strategy before writing any functional code.

---

## Minor Pitfalls

---

### Pitfall 10: Insecure Temporary File in /tmp

**What goes wrong:** The temp file used to pass text to/from vim is created with a predictable name in `/tmp`, which is world-writable. A malicious local process could pre-create the file as a symlink to an arbitrary target, causing the app to write the user's clipboard contents to that target.

**Why it happens:** Simple implementations do `let path = "/tmp/vim-anywhere-edit.txt"` without uniqueness or atomic creation.

**Prevention:**
- Use `FileManager.default.temporaryDirectory` to get a per-user temp directory (macOS returns `$TMPDIR`, which is per-user and inside a sandboxed container for the session).
- Append a UUID: `temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")`.
- Delete the file in a `defer` block or `finally` equivalent after the paste step — including on all error paths (vim crash, user abort).

**Warning signs:**
- Temp file path is hardcoded or predictable.
- Cleanup only happens on the happy path (`:wq` success).

**Phase:** Core edit cycle phase.

---

### Pitfall 11: Vim Not Found at Runtime

**What goes wrong:** The app launches `/usr/bin/vim` or assumes `vim` is on `$PATH`. On a fresh macOS install (particularly Apple Silicon), `/usr/bin/vim` may not exist or may be a stub that requires Xcode Command Line Tools. On systems where vim is installed via Homebrew, it may be at `/opt/homebrew/bin/vim` (Apple Silicon) or `/usr/local/bin/vim` (Intel).

**Prevention:**
- At startup, search a priority list of known vim locations: `/usr/bin/vim`, `/opt/homebrew/bin/vim`, `/usr/local/bin/vim`.
- Alternatively, resolve `vim` using `/usr/bin/env vim` via a login shell (`/bin/zsh -l -c "which vim"`) to respect the user's PATH.
- If vim is not found, surface a clear error in the menu bar rather than silently failing when the trigger fires.

**Warning signs:**
- Works in development (developer has Homebrew vim) but fails for end users.
- App trigger fires, a terminal window flashes briefly, then nothing happens.

**Phase:** Foundation phase.

---

### Pitfall 12: Swift Concurrency / Main Thread Violations in CGEvent Callbacks

**What goes wrong:** CGEvent tap callbacks execute on a background thread. Touching AppKit objects (showing a window, updating `NSStatusItem`, writing to `NSPasteboard`) from a CGEvent callback without dispatching to the main thread causes crashes or undefined behavior.

**Why it happens:** CGEventTap callbacks are C-style function pointers running on a RunLoop in the event stream — not on the main queue. Swift 6's strict concurrency checking may surface this as a compile error (reference to variables is not concurrency-safe without `@preconcurrency` import).

**Prevention:**
- Always dispatch UI and pasteboard operations from the event tap callback to `DispatchQueue.main.async`.
- Under Swift 6, add `import ApplicationServices` via `@preconcurrency import ApplicationServices` if needed.
- Never perform blocking work (file I/O, process launch) inside the tap callback — dispatch it and return immediately.

**Warning signs:**
- Occasional crashes in AppKit/Foundation during event tap callbacks.
- Swift 6 compiler errors about concurrency safety in event tap handler.

**Phase:** Foundation phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Event tap setup | Silent tap (Pitfall 1) | Health monitor timer + handle tapDisabledByTimeout |
| Permission prompts | One-time check (Pitfall 2) | Poll AXIsProcessTrusted on timer until granted |
| Grab text (Cmd+A, Cmd+C) | Timing race (Pitfall 4) | Delays + changeCount polling to confirm copy |
| Paste text back (Cmd+V) | Focus not restored (Pitfall 7) | Capture frontmost app at trigger; restore before paste |
| Clipboard safety | Clipboard clobber (Pitfall 3) | Save/restore NSPasteboard before any clipboard mutation |
| Hotkey design | Double-tap false positives (Pitfall 6) | Full modifier state machine + debounce window |
| Development workflow | TCC reset on rebuild (Pitfall 9) | Developer ID signing from day one |
| App shell | NSStatusItem released (Pitfall 8) | Store as property on AppDelegate |
| Temp file I/O | Insecure /tmp (Pitfall 10) | Use $TMPDIR + UUID filename |
| Vim invocation | Vim not found (Pitfall 11) | Priority-list search at startup; clear error state |
| CGEvent callbacks | Main thread violations (Pitfall 12) | Always dispatch to main queue from tap callback |
| Target app compatibility | Electron/web fields (Pitfall 5) | Document limitations; test matrix early |

---

## Sources

- [CGEventType.tapDisabledByTimeout — Apple Developer Documentation](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout)
- [CGEvent Taps and Code Signing: The Silent Disable Race — Daniel Raffel](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/)
- [Accessibility Permission in macOS — jano.dev (2025)](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
- [Implementing Auto-Type on macOS — Igor Kulman](https://blog.kulman.sk/implementing-auto-type-on-macos/)
- [FB12113281: CGEvent.tapCreate stops receiving events — feedback-assistant/reports](https://github.com/feedback-assistant/reports/issues/390)
- [Identifying and Handling Transient or Special Data on the Clipboard — NSPasteboard.org](http://nspasteboard.org/)
- [vim-anywhere issue #61: Keep previous clipboard](https://github.com/cknadler/vim-anywhere/issues/61)
- [vim-anywhere issue #81: Insecure use of /tmp](https://github.com/cknadler/vim-anywhere/issues/81)
- [Race Conditions and Secure File Operations — Apple Developer (archive)](https://developer.apple.com/library/archive/documentation/Security/Conceptual/SecureCodingGuide/Articles/RaceConditions.html)
- [Text selection via accessibility broken in Electron — electron/electron #36337](https://github.com/electron/electron/issues/36337)
- [A service class for monitoring global keyboard events in macOS Swift — stephancasas gist](https://gist.github.com/stephancasas/fd27ebcd2a0e36f3e3f00109d70abcdc)
- [CGPreflightListenEventAccess — Apple Developer Documentation](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess())
