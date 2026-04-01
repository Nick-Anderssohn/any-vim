<!-- GSD:project-start source:PROJECT.md -->
## Project

**AnyVim**

A macOS menu bar utility that lets you use vim to edit text in any text field across any application. Double-tap the Control key to open vim with the current text field's contents, edit freely, and :wq to send the edited text back to the original text field.

**Core Value:** Seamless vim editing in any text input on macOS — the trigger-edit-return loop must feel instant and reliable.

### Constraints

- **Language**: Swift preferred — macOS Accessibility APIs, global event monitoring, and menu bar integration are all native AppKit/Cocoa APIs with no practical Go equivalent
- **Platform**: macOS only (uses platform-specific APIs throughout)
- **Permissions**: Requires Accessibility and Input Monitoring permissions — app must handle the case where these aren't granted
- **Binary size**: Should be small — no heavy frameworks beyond what macOS provides
- **Startup time**: Must launch quickly and stay lightweight in the background
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Language and Runtime
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Swift | 6.1 (Xcode 16.3) | Primary language | Native AppKit/CoreGraphics APIs with zero FFI friction. Accessibility APIs, CGEventTap, NSStatusItem, and Process are all first-class Swift. Go would require unsafe C bridging for every one of these layers. |
| Swift Language Mode | Swift 6 | Concurrency safety | New Xcode 26 projects default to MainActor isolation. For a menu bar daemon that is fundamentally single-threaded (wait for hotkey → act → wait), this is the right default and avoids data race warnings. |
### Menu Bar Integration
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| AppKit — NSStatusBar / NSStatusItem | macOS 13+ SDK | Menu bar icon and menu | Use AppKit directly, not SwiftUI MenuBarExtra. MenuBarExtra has documented timing delays, non-native dismiss behavior, and less control over layout. For a background daemon with a minimal "Quit" menu, raw NSStatusItem is 10 lines of code and behaves exactly like system utilities. |
### Global Keyboard Monitoring
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| CGEventTap (CoreGraphics) | macOS 13+ | Detect double-tap Control globally | The only supported macOS mechanism for intercepting system-wide keyboard events before they reach other apps. Requires Accessibility permission (defaultTap mode) since we need to observe and optionally consume the event. |
- Use `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback:...)` — requires Accessibility permission, not just Input Monitoring.
- Double-tap detection: track timestamps of consecutive Control keyDown events. If two keyDown events for `kVK_Control` arrive within ~300ms, trigger the workflow.
- **Critical:** A non-nil tap is not a healthy tap. Code-signing identity changes (re-signing during dev) silently disable the tap. Implement a periodic `CGEvent.tapIsEnabled()` health check and reinstall if needed. Source: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/
### Accessibility API (Text Field Interaction)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| AXUIElement (ApplicationServices) | macOS 13+ | Simulate Cmd+A/Cmd+C/Cmd+V in the focused app | Standard macOS mechanism for programmatically interacting with UI elements in other apps. No third-party library is needed. |
| CGEvent.post (CoreGraphics) | macOS 13+ | Synthesize keystrokes | Send Cmd+A, Cmd+C, Cmd+V to the previously focused application by posting CGEvents to the .cghidEventTap. |
- Before triggering, capture `AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute` → `kAXFocusedUIElementAttribute` to know where to restore focus.
- To read text: post `Cmd+A` then `Cmd+C` via `CGEvent.post`, wait ~50ms for the pasteboard to update, read `NSPasteboard.general`.
- To write text: set `NSPasteboard.general` content, post `Cmd+A` then `Cmd+V` via `CGEvent.post`.
- Preserve the clipboard: snapshot `NSPasteboard.general` contents before the read step, restore after the paste step.
- **AXSwift** (github.com/tmandry/AXSwift) — last released in September 2021 (v0.3.2), not actively maintained. The raw AXUIElement C API is straightforward enough to use directly for this use case.
- **AXorcist** — actively maintained but designed for UI testing automation pipelines. Heavier than necessary.
### Terminal / Vim Hosting
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| SwiftTerm — LocalProcessTerminalView | 1.13.0 (March 2026) | Embedded terminal emulator in an NSWindow | SwiftTerm provides a ready-made AppKit NSView that connects to a Unix PTY and runs a subprocess (vim). This gives a proper terminal that vim can drive — colors, cursor movement, raw mode — without launching Terminal.app or any external terminal emulator. Actively maintained (1.4k stars, commercial SSH clients use it). |
| NSPanel (AppKit) | macOS 13+ | Floating window for the terminal | NSPanel with `.floating` window level keeps the vim window above other apps without stealing menu bar focus. |
| Foundation.Process | macOS 13+ | (Fallback only) | Not recommended as primary approach — vim requires a PTY. SwiftTerm handles the PTY plumbing internally. |
- **Launching Terminal.app via `NSWorkspace.open`** — no control over the window, no reliable way to know when `:wq` completes, window management is outside app control.
- **MacVim or gVim** — the original vim-anywhere used MacVim. This is a dependency that many devs won't have. vim (CLI) is included with macOS and available via Homebrew.
- **Embedding Neovim (VimR/NvimView approach)** — AnyVim is vim-only per spec. NvimView bundles the entire Neovim binary (large, different config than `~/.vimrc`).
### Build System
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Swift Package Manager | Built into Xcode 16.3 | Dependency management | SwiftTerm and Sparkle are both available as SPM packages. No CocoaPods or Carthage needed. |
| Xcode | 16.3 | Build and code signing | Required for code signing. Must be properly signed (Developer ID or development certificate) for CGEventTap to work — TCC ties permissions to code identity. |
### Auto-Update (Optional, Post-MVP)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Sparkle | 2.9.1 (March 2025) | In-app update mechanism | The de facto standard for non-App-Store macOS app updates. Supports sandboxed and non-sandboxed apps. Actively maintained (63 releases). |
## macOS Deployment Target
- macOS 15 (Sequoia) commanded 66%+ of active installs by March 2025 and macOS 14+ combined is well above 80%.
- macOS 13 is the oldest version still receiving security updates as of early 2026.
- All APIs used (CGEventTap, AXUIElement, NSStatusItem, SwiftTerm) are available on macOS 13+.
- No meaningful APIs in this project require macOS 14 or 15 specifically.
- Targeting macOS 12 (Monterey) is unnecessary — it is outside Apple's support window and adoption is marginal.
## Alternatives Considered
| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Language | Swift | Go | Go has no native AppKit/CoreGraphics bindings. CGEventTap, AXUIElement, NSStatusItem would all require CGo FFI — fragile, complex, and defeats the purpose. |
| Language | Swift | Objective-C | Swift is the current standard. Same API access, better tooling, better concurrency model. |
| Menu Bar UI | AppKit NSStatusItem | SwiftUI MenuBarExtra | MenuBarExtra has timing/dismiss quirks for simple daemon use cases. NSStatusItem is 10 lines and behaves exactly like system utilities. |
| Global Hotkey | CGEventTap | NSEvent global monitor | NSEvent monitor is passive only (cannot swallow events) and has less fidelity for modifier-only keys. |
| Terminal hosting | SwiftTerm | Launch Terminal.app | No lifecycle control, no window management, no reliable `:wq` detection. |
| Terminal hosting | SwiftTerm | NSTask + pipe (no PTY) | vim requires a PTY. Without one, vim starts in non-interactive mode and renders broken output. |
| Accessibility wrapper | Raw AXUIElement | AXSwift | AXSwift is unmaintained (last release 2021). Raw API is sufficient for Cmd+A/C/V simulation. |
## Installation (Package.swift dependencies)
## Required Entitlements and Info.plist Keys
## Sources
- SwiftTerm GitHub: https://github.com/migueldeicaza/SwiftTerm (v1.13.0, March 2026)
- Sparkle releases: https://github.com/sparkle-project/sparkle/releases (v2.9.1, March 2025)
- AXSwift GitHub: https://github.com/tmandry/AXSwift (v0.3.2, last maintained 2021)
- CGEvent tap code signing pitfall: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/
- Swift 6.1 release: https://www.swift.org/blog/swift-6.1-released/
- AppKit menu bar best practices: https://www.polpiella.dev/a-menu-bar-only-macos-app-using-appkit/
- CGEventTap permission nuances: https://developer.apple.com/forums/thread/122492
- macOS adoption data: https://telemetrydeck.com/survey/apple/macOS/versions/
- SwiftTerm LocalProcessTerminalView docs: https://migueldeicaza.github.io/SwiftTerm/Classes/LocalProcessTerminalView.html
- AXUIElement Apple docs: https://developer.apple.com/documentation/applicationservices/axuielement
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
