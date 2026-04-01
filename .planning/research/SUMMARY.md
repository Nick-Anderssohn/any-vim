# Project Research Summary

**Project:** AnyVim
**Domain:** macOS menu bar utility — system-wide "edit in vim" daemon
**Researched:** 2026-03-31
**Confidence:** HIGH

## Executive Summary

AnyVim is a macOS background daemon that intercepts a global double-tap Control hotkey, grabs text from the currently focused field, opens it in a purpose-built embedded terminal running vim, and pastes the edited text back — all without the user leaving their current application. This is a well-understood product category (vim-anywhere, osx-vimr-anywhere) with established patterns, clear API choices, and documented failure modes. The right implementation is a lean, unsigned-hostile, native Swift app using only Apple-first APIs (CGEventTap, AXUIElement, NSStatusItem) plus one carefully-chosen third-party library for PTY-backed vim hosting (SwiftTerm).

The recommended approach is Swift 6 targeting macOS 13+, with no App Sandbox (Accessibility API requires it disabled), distributed as a direct download or Homebrew cask. The architecture is a six-component linear pipeline: AppShell owns the process lifetime; HotkeyMonitor drives the CGEventTap on a dedicated thread; EditCycleCoordinator sequences AccessibilityBridge, TempFileStore, and VimLauncher as an async/await chain. App Sandbox incompatibility means no Mac App Store — Sparkle handles auto-update post-MVP if needed. The build order is well-defined and phases are largely independent after the foundation is in place.

The dominant risks are not design risks — they are implementation-level gotchas specific to this class of macOS utility. Three issues routinely cause rewrites or serious reliability failures: silent event tap death due to code-signing identity changes, permission state not being re-polled after the user grants access, and clipboard clobber on any non-happy-path exit. All three have reliable mitigations that must be built in from the start, not added later. Secondary risks — timing races in keystroke simulation, focus not being restored before paste, Electron app incompatibility — are moderate and can be managed with explicit test targets and documented workarounds.

---

## Key Findings

### Recommended Stack

Swift 6 on macOS 13+ is the only practical choice. The core APIs (CGEventTap, AXUIElement, NSStatusItem) are C/Objective-C APIs surfaced natively in Swift with zero FFI; any other language requires C bridging at every boundary. The project must run outside the App Sandbox — Accessibility API access to other processes is sandbox-incompatible, which also means no App Store distribution. SwiftTerm (v1.13.0) is the right embedded terminal library: it provides a PTY-backed VT100 terminal as an AppKit NSView, is actively maintained, and exposes `TerminalViewDelegate.processTerminated` to detect vim exit. Raw AppKit (NSStatusItem, not SwiftUI MenuBarExtra) is correct for the minimal menu bar presence this daemon needs.

**Core technologies:**
- **Swift 6.1 / Xcode 16.3**: Primary language — native access to all required Apple APIs, no FFI, MainActor isolation matches single-threaded daemon model
- **CGEventTap (CoreGraphics)**: Global hotkey interception — only supported macOS mechanism; used by Alfred, Raycast, Karabiner internally
- **AXUIElement + CGEvent.post (ApplicationServices / CoreGraphics)**: Text grab and paste — works across arbitrary apps without target-app cooperation
- **SwiftTerm LocalProcessTerminalView (v1.13.0)**: Embedded PTY-backed terminal — avoids Terminal.app focus-stealing and lifecycle uncertainty; exposes process termination callback
- **NSStatusItem (AppKit)**: Menu bar icon — raw AppKit preferred over SwiftUI MenuBarExtra for daemon-style apps
- **Swift Package Manager**: Dependency management — SwiftTerm and Sparkle (post-MVP) are both on the Swift Package Index
- **Sparkle 2.9.1** (post-MVP only): Auto-update — de facto standard for non-App-Store macOS utilities

**Critical constraint:** `LSUIElement = true` (no Dock icon) and App Sandbox must be **off**. Bundle ID must be stable from day one — TCC permission grants are tied to code identity.

### Expected Features

The core user contract is simple: trigger → grab → edit → paste-back with clipboard intact. Every feature in the MVP flows from this chain. Anything outside it is a differentiator or post-v1.

**Must have (table stakes):**
- Global double-tap Control hotkey — no hotkey, no product; must work in all apps including browsers and Electron
- Grab existing text from focused field via Cmd+A/Cmd+C — users expect their text pre-loaded in vim
- Write back on `:wq` — temp file read + Cmd+A/Cmd+V paste after vim process exits
- Clipboard preservation — save/restore NSPasteboard contents around the grab/paste cycle; vim-anywhere issue #61 is a long-standing complaint
- Works in browsers and native Cocoa apps — the primary use cases
- Menu bar icon with Quit item — standard background utility UX on macOS
- Accessibility + Input Monitoring permission onboarding — required before any core flow works; must not require restart after granting
- Respects user's `~/.vimrc` — just launch system vim, it picks up vimrc automatically
- Graceful abort on `:q!` — check whether temp file was modified before pasting back
- Temp file cleanup — delete after paste or abort; use `$TMPDIR` + UUID, not `/tmp` with a predictable name

**Should have (differentiators):**
- Lightweight dedicated terminal window via SwiftTerm — avoids Terminal.app focus/lifecycle issues; major UX differentiator over vim-anywhere's MacVim approach
- Visual indicator in menu bar while edit session is active — animate/change status icon
- Start-in-insert-mode option — launch vim with `+startinsert`; low complexity, high value for power users
- Configurable vim binary path — preference item; supports Homebrew vim vs `/usr/bin/vim`
- File type hint via temp file extension — name temp file `.md` for markdown contexts; low complexity

**Defer (v2+):**
- Edit history / temp file persistence — keep recent edits in `~/.local/share/any-vim/history/` rather than cleaning up immediately
- Electron/complex web app fallback strategies — high complexity, high breakage risk; document limitations for v1
- Browser address bar support — finicky focus/refocus behavior; validate demand
- Custom hotkey configuration — defer; double-tap Control is a good default

**Anti-features (never build):**
- Neovim support, vim-mode overlay, browser extension, plugin system, bundled vim binary, multi-editor support, App Store distribution

### Architecture Approach

AnyVim maps cleanly onto seven components with a linear data flow. The architecture is a persistent background layer (AppShell + HotkeyMonitor) that feeds into a single-use-per-invocation EditCycleCoordinator, which sequences three mutually independent sub-components. The cycle is expressed as an async/await chain: each step is `async throws`; VimLauncher wraps `Process.terminationHandler` in a `withCheckedThrowingContinuation`. The CGEventTap runs on a dedicated CFRunLoop thread (never the main thread); the tap callback dispatches to `DispatchQueue.main.async` for all UI and pasteboard work.

**Major components:**
1. **AppShell** — NSStatusItem lifecycle, menu, PermissionGuard gate at startup, owns HotkeyMonitor
2. **PermissionGuard** — AXIsProcessTrusted + CGPreflightListenEventAccess checks; polls on timer after permission prompt until granted; blocks EditCycle if not satisfied
3. **HotkeyMonitor** — CGEventTap on dedicated CFRunLoop thread; double-tap state machine using `flagsChanged` events + debounce window
4. **AccessibilityBridge** — AXUIElement focused-element lookup; Cmd+A/Cmd+C synthesis to read; Cmd+A/Cmd+V to paste; NSPasteboard snapshot/restore
5. **TempFileStore** — write to `$TMPDIR/<UUID>.txt`; read back after edit; delete in `defer` block covering all exit paths
6. **VimLauncher** — SwiftTerm NSWindow hosting vim process; blocks via Process.terminationHandler until exit
7. **EditCycleCoordinator** — async/await orchestration of steps 1-7 of the edit cycle; guards against re-entrant invocations via `isEditing` flag

**Build order:** PermissionGuard → AppShell → HotkeyMonitor → (AccessibilityBridge + TempFileStore + VimLauncher in parallel) → EditCycleCoordinator → integration wiring

### Critical Pitfalls

1. **Silent event tap death** — CGEventTap returns non-nil but receives nothing after a rebuild or re-sign. Add a 5-second health-check timer calling `CGEvent.tapIsEnabled(tap:)` and re-install if false. Handle `kCGEventTapDisabledByTimeout` in the callback. Sign with Developer ID from day one.

2. **Permission state cached at launch** — `AXIsProcessTrusted()` checked once then never again. After the permission prompt, poll on a 2-second timer until the value becomes true, then proceed without requiring restart.

3. **Clipboard clobber on any non-happy exit** — NSPasteboard contents destroyed by Cmd+C / Cmd+V simulation. Snapshot all pasteboard types (not just plain text) before the grab step. Restore unconditionally in a `defer` block — on vim crash, user abort, timeout, or error.

4. **Timing races in simulated keystrokes** — `CGEvent.post` returns immediately; target app may not have processed Cmd+A before Cmd+C fires. Use 150ms minimum delay between Cmd+A and Cmd+C; poll `NSPasteboard.changeCount` to confirm copy happened rather than assuming it after a fixed delay.

5. **Focus not restored before paste** — macOS does not reliably return focus to the previous app after a floating window closes. Capture `NSWorkspace.shared.frontmostApplication` at trigger time; call `previousApp.activate(options: .activateIgnoringOtherApps)` after vim exits; wait 100-200ms before posting paste events.

Additional pitfalls requiring early mitigation: TCC permission reset on rebuild without Developer ID (Pitfall 9 — set up signing in Phase 1); NSStatusItem released if stored as local variable (Pitfall 8 — store as AppDelegate property); Swift 6 main thread violations in CGEvent callbacks (Pitfall 12 — always `DispatchQueue.main.async`).

---

## Implications for Roadmap

Architecture research defines a clear build order with hard dependencies. The phases below follow component dependencies, not arbitrary chunking.

### Phase 1: App Shell and Foundation

**Rationale:** AppShell + PermissionGuard must exist before any other component can run. Code-signing identity must be established before any functional code is written — TCC resets on rebuild without Developer ID (Pitfall 9) will otherwise poison all subsequent development. Menu bar icon stored incorrectly causes it to vanish (Pitfall 8).
**Delivers:** Runnable background agent with menu bar icon, Quit item, permission detection, and re-poll-after-grant flow
**Addresses:** Menu bar presence (table stakes), permission onboarding (table stakes)
**Avoids:** NSStatusItem release bug (Pitfall 8), TCC reset on rebuild (Pitfall 9), permission state not re-polled (Pitfall 2)
**Stack:** NSStatusItem/AppKit, LSUIElement, `AXIsProcessTrusted`, Developer ID signing

### Phase 2: Global Hotkey Detection

**Rationale:** HotkeyMonitor requires AppShell's RunLoop to be running. This phase is the second hard dependency — nothing fires without a working hotkey. The state machine for double-tap detection is non-trivial and must be validated in isolation before being wired to the edit cycle.
**Delivers:** Reliable double-tap Control detection that does not false-positive on normal keyboard use
**Addresses:** Global hotkey trigger (table stakes)
**Avoids:** Silent event tap (Pitfall 1 — health monitor timer), double-tap false positives (Pitfall 6 — `flagsChanged` state machine + debounce), Swift 6 main thread violations (Pitfall 12)
**Stack:** CGEventTap on dedicated CFRunLoop thread

### Phase 3: Accessibility Bridge and Clipboard

**Rationale:** AccessibilityBridge and TempFileStore are independent of VimLauncher and can be built and tested in parallel with Phase 4. Clipboard snapshot/restore is the highest-risk correctness concern — it must be built as part of this phase, not added later as an afterthought.
**Delivers:** Reliable text grab from focused fields and paste-back, with clipboard fully preserved across all exit paths
**Addresses:** Grab existing text (table stakes), write back on :wq (table stakes), clipboard restoration (table stakes), works in browsers/native apps (table stakes)
**Avoids:** Clipboard clobber (Pitfall 3 — snapshot in `defer`), timing races (Pitfall 4 — delays + changeCount polling), focus not restored (Pitfall 7 — capture frontmost app at trigger time)
**Stack:** AXUIElement, CGEvent.post, NSPasteboard

### Phase 4: Vim Launch and Terminal Window

**Rationale:** VimLauncher is independent of AccessibilityBridge but requires TempFileStore (file path). Building SwiftTerm integration here — rather than deferring to polish — is the right call because it eliminates Terminal.app lifecycle uncertainty and is central to the product's UX differentiation. Process termination detection via `TerminalViewDelegate.processTerminated` must be verified against the actual SwiftTerm API.
**Delivers:** Floating terminal window that hosts vim, closes on `:wq`/`:q!`, and signals process exit reliably
**Addresses:** Lightweight dedicated terminal window (differentiator), write back on `:wq` (table stakes), graceful abort on `:q!` (table stakes), uses user's `~/.vimrc` (table stakes)
**Avoids:** Terminal.app focus-stealing (Anti-Pattern 5), polling for vim exit via timer (Anti-Pattern 3), vim not found (Pitfall 11 — priority-list search at startup)
**Stack:** SwiftTerm 1.13.0, NSPanel with `.floating` window level, Foundation.Process

### Phase 5: Edit Cycle Integration

**Rationale:** EditCycleCoordinator wires Phases 2, 3, and 4 together. It cannot exist before its sub-components. This phase is where the full user workflow becomes testable end-to-end.
**Delivers:** Complete trigger → grab → edit → paste-back cycle with re-entrancy protection and temp file cleanup
**Addresses:** Full table-stakes feature set operational
**Avoids:** Re-entrant edit cycles (isEditing guard), insecure /tmp temp file (Pitfall 10 — `$TMPDIR` + UUID), all timing issues via async/await chain with explicit delays
**Stack:** Swift async/await, withCheckedThrowingContinuation for Process.terminationHandler

### Phase 6: Polish and Edge Cases

**Rationale:** Post-integration hardening. Visual feedback, configurable preferences, and edge-case handling are all safe to defer until the core cycle is solid.
**Delivers:** Visual indicator during active edit session, start-in-insert-mode option, configurable vim binary path, file type hint via temp file extension, documented Electron/browser limitations
**Addresses:** Differentiator features; Electron compatibility documented as known limitation
**Avoids:** Scope creep from v2+ features (Neovim, custom hotkeys, edit history, browser extension)

### Phase Ordering Rationale

- Phases 1 and 2 are strictly sequential — each is a hard prerequisite for the next
- Phases 3 and 4 are independent of each other and can be built in parallel if desired
- Phase 5 requires completion of Phases 2, 3, and 4
- Phase 6 requires Phase 5 and has no internal dependencies
- Clipboard preservation (Pitfall 3) is placed in Phase 3, not Phase 5, because retrofitting it later is error-prone — all error exit paths must be in scope when designing the snapshot/restore
- Developer ID signing is placed in Phase 1 (not "later") because TCC grants are code-identity-dependent from the first run

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (VimLauncher/SwiftTerm):** SwiftTerm integration for the specific AnyVim use case (embed, detect `:wq`, close window) needs hands-on validation. ARCHITECTURE.md rates SwiftTerm confidence as MEDIUM. Verify `TerminalViewDelegate.processTerminated` API signature and window lifecycle management before committing to implementation design.
- **Phase 3 (AccessibilityBridge timing):** The correct delay values for Cmd+A → Cmd+C and focus-restore → Cmd+V are empirically determined. Research should include testing against the baseline app matrix (TextEdit, Notes, Safari, Chrome, VS Code, Slack) to characterize variance.

Phases with standard patterns (skip research-phase):
- **Phase 1 (App Shell):** NSStatusItem + LSUIElement is extremely well-documented. AppKit menu bar patterns are stable and have multiple quality tutorials.
- **Phase 2 (HotkeyMonitor):** CGEventTap double-tap pattern is well-established in open-source macOS utilities (alt-tab-macos, EventTapper). Keycode 59 for Control confirmed. The `flagsChanged`-based state machine is the correct pattern.
- **Phase 5 (Coordinator):** async/await + withCheckedThrowingContinuation is standard Swift concurrency. No novel patterns.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All primary technologies are Apple-first APIs with official docs. SwiftTerm is the one third-party dependency and confidence is MEDIUM-HIGH — actively maintained, correct capability set, specific integration needs hands-on verification. |
| Features | HIGH | Table stakes derived from vim-anywhere source, active GitHub issues, and HN discussion. Differentiator classification is mostly HIGH with two MEDIUM-confidence items (lightweight terminal window, Electron support complexity). |
| Architecture | MEDIUM-HIGH | Component boundaries and data flow are clearly derived from API constraints. CGEventTap threading pattern rated MEDIUM by researcher (community patterns, not Apple sample code). SwiftTerm integration rated MEDIUM. Everything else is HIGH. |
| Pitfalls | HIGH | Critical pitfalls (1, 2, 3, 4, 7) are sourced from primary docs, known vim-anywhere issues, and a specific CGEventTap code-signing post with direct citations. Pitfalls 5 (Electron) and 6 (double-tap false positives) are MEDIUM — well-understood problem, mitigation is best-effort. |

**Overall confidence:** HIGH

### Gaps to Address

- **SwiftTerm NSWindow lifecycle for modal vim session:** `TerminalViewDelegate.processTerminated` exists per README, but the exact interaction between window close, process termination, and the async continuation needs a spike before Phase 4 design is finalized.
- **Delay tuning for simulated keystrokes:** 150ms (Cmd+A → Cmd+C) and 200ms (focus restore → Cmd+V) are community-reported values. These should be validated empirically against the test matrix during Phase 3 implementation, not treated as fixed constants.
- **Control keycode on non-US keyboards:** Keycode 59 is the left Control key on US layouts. Right Control is keycode 62. Non-US keyboards may differ. The HotkeyMonitor should handle both left and right Control, and this should be validated during Phase 2.
- **macOS 13 deployment target finality:** Recommended based on adoption data from early 2025. Should be re-confirmed at distribution time given the March 2026 research date.

---

## Sources

### Primary (HIGH confidence)
- SwiftTerm GitHub (v1.13.0, March 2026) — terminal emulator capabilities, processTerminated callback
- Apple Developer Documentation — CGEventTap, AXUIElement, NSStatusItem, NSPasteboard
- vim-anywhere GitHub (cknadler) + open issues #61, #81, #94 — feature expectations, known bugs
- Swift 6.1 release notes — MainActor isolation, concurrency model
- Daniel Raffel TIL (2026-02-19) — CGEventTap silent disable race condition with code signing

### Secondary (MEDIUM confidence)
- alt-tab-macos KeyboardEvents.swift — CGEventTap threading patterns
- EventTapper (usagimaru) — double-tap state machine patterns
- jano.dev Accessibility Permission guide (2025) — AXIsProcessTrusted polling pattern
- polpiella.dev AppKit menu bar guide — NSStatusItem best practices
- TelemetryDeck macOS adoption survey — macOS 13+ deployment target rationale
- SwiftUI global key events guide (levelup.gitconnected.com) — CGEventTap vs NSEvent comparison

### Tertiary (LOW confidence)
- Medium: "All the ways to use Vim outside of Vim on macOS" — ecosystem overview
- Hacker News vim-anywhere discussion — user sentiment and feature requests

---
*Research completed: 2026-03-31*
*Ready for roadmap: yes*
