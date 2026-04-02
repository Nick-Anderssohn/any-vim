# Phase 6: Polish and Configuration - Research

**Researched:** 2026-04-02
**Domain:** AppKit NSStatusItem icon management, UserDefaults persistence, NSOpenPanel, Swift protocol extension
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Session Indicator (MENU-02)**
- **D-01:** Swap the SF Symbol during an active vim session. Idle state uses `character.cursor.ibeam` (existing). Active state uses a different SF Symbol (e.g., `pencil.circle.fill` or `pencil.and.outline`). Both in template mode so they adapt to dark/light menu bar automatically.
- **D-02:** Icon swap is the sole visual indicator. No additional "Session: Active" menu item in the dropdown. Consistent with Phase 1 D-06 (minimal menu).
- **D-03:** Icon updates happen at the start and end of `handleHotkeyTrigger` — set active icon before `captureText`, restore idle icon after all cleanup completes (including abort paths).

**Vim Path Configuration (CONF-01)**
- **D-04:** Add a "Set Vim Path..." menu item that opens an NSOpenPanel file picker. User selects a binary, path is stored in UserDefaults. A "Reset Vim Path" menu item restores PATH-based resolution.
- **D-05:** Menu shows the currently resolved vim path as a disabled info item (e.g., "Vim: /opt/homebrew/bin/vim"). Updates when custom path is set or reset.
- **D-06:** Validate on set — verify the selected file exists and is executable before saving. On each trigger, if the stored custom path is invalid, fall back to PATH resolution silently. Menu shows "(custom path invalid)" so the user knows.
- **D-07:** Custom path stored in UserDefaults under a key like `customVimPath`. When nil/empty, the existing `ShellVimPathResolver` PATH-based resolution is used. When set, the stored path takes precedence.

### Claude's Discretion
- Exact SF Symbol choice for the active-session icon (within the pencil/edit family)
- How to integrate the vim path display and picker into `MenuBarController.buildMenu()` (menu item ordering, separator placement)
- Whether to create a `VimPathConfigManager` class or add methods to existing `VimSessionManager`
- How `VimPathResolving` protocol adapts to check UserDefaults before PATH resolution
- NSOpenPanel configuration details (allowed file types, initial directory)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MENU-02 | Menu bar icon animates or changes while a vim session is active | SF Symbol swap via `statusItem.button.image` — one-liner; `isEditSessionActive` already tracks session state in AppDelegate |
| CONF-01 | User can configure the path to the vim binary (defaults to vim in PATH) | `VimPathResolving` protocol already injectable; `UserDefaults` pattern already used for `VimWindowFrame`; NSOpenPanel provides the file picker |
</phase_requirements>

---

## Summary

Phase 6 is entirely additive polish with no new subsystems. Both requirements hook into well-established patterns already present in the codebase. MENU-02 is a one-liner icon swap driven by the `isEditSessionActive` guard that exists on AppDelegate since Phase 5. CONF-01 requires a thin wrapper resolver (`UserDefaultsVimPathResolver`) that checks UserDefaults before falling back to `ShellVimPathResolver`, plus three new menu items in `MenuBarController.buildMenu()`.

The key design decision Claude has discretion over is whether to create a `VimPathConfigManager` class or add the UserDefaults read/write logic directly to a new resolver struct. Given the project's established pattern of thin protocol-typed structs (see `ShellVimPathResolver`, `SystemPasteboard`, etc.), a new resolver struct is the natural fit — no separate manager class is needed for state that is purely persisted in UserDefaults.

NSOpenPanel must be called on the main thread (which is already guaranteed by `@MainActor` isolation on `MenuBarController`). UserDefaults writes are synchronous and safe on the main actor. No async work is introduced.

**Primary recommendation:** Add `UserDefaultsVimPathResolver` (a composing struct that checks UserDefaults then delegates to `ShellVimPathResolver`) and wire icon swaps into the two existing entry/exit sites in `handleHotkeyTrigger`. Everything else follows from existing patterns.

---

## Standard Stack

### Core (all already in the project — no new dependencies)

| API | Version | Purpose | Why |
|-----|---------|---------|-----|
| `NSStatusItem.button.image` | macOS 13+ | Menu bar icon swap | Already set up with SF Symbol in template mode; reassigning `image` is instantaneous and thread-safe on main actor |
| `NSImage(systemSymbolName:)` | macOS 11+ | Load SF Symbol | Already used in `AppDelegate.applicationDidFinishLaunching` — same pattern for both idle and active images |
| `NSOpenPanel` | macOS 13+ | File picker for vim binary | Standard AppKit panel; no third-party library needed |
| `UserDefaults.standard` | macOS 13+ | Persist custom vim path | Already used for `VimWindowFrame` in `VimSessionManager` — identical pattern |
| `FileManager.default` | macOS 13+ | Validate binary exists and is executable | `FileManager.fileExists(atPath:)` + `FileManager.isExecutableFile(atPath:)` |

### No New Dependencies

This phase requires zero new SPM packages. All APIs are AppKit/Foundation already imported.

---

## Architecture Patterns

### Recommended Project Structure (additions only)

```
Sources/AnyVim/
├── AppDelegate.swift          -- Add icon swap calls (2 lines)
├── MenuBarController.swift    -- Add vim path section (3 menu items + actions)
├── SystemProtocols.swift      -- Add UserDefaultsVimPathResolver struct
└── VimSessionManager.swift    -- No changes (VimPathResolving injection unchanged)

AnyVimTests/
├── MenuBarControllerTests.swift  -- Add vim path section tests
└── VimSessionManagerTests.swift  -- Add UserDefaultsVimPathResolver tests
```

### Pattern 1: Icon Swap at Session Boundaries (MENU-02)

**What:** Reassign `statusItem.button.image` at session start and end.
**When to use:** Any state change that should be reflected in the menu bar icon.

**Implementation:**
```swift
// In AppDelegate (existing handleHotkeyTrigger Task body)
// D-03: set active icon BEFORE captureText
statusItem.button?.image = NSImage(systemSymbolName: "pencil.circle.fill",
                                    accessibilityDescription: "AnyVim — editing")
statusItem.button?.image?.isTemplate = true

// D-02: defer ensures icon restores on ALL exit paths (saved, aborted, captureText failure)
defer {
    isEditSessionActive = false
    statusItem.button?.image = NSImage(systemSymbolName: "character.cursor.ibeam",
                                        accessibilityDescription: "AnyVim")
    statusItem.button?.image?.isTemplate = true
}
```

The `defer` block already resets `isEditSessionActive = false`. The icon restore fits naturally in the same `defer` so it is guaranteed to run on every exit path. Source: existing AppDelegate defer pattern (Phase 5 D-02).

**Note on image.isTemplate:** `NSImage(systemSymbolName:)` returns an image that is NOT automatically a template. `isTemplate` must be set explicitly after construction or the icon will not adapt to the menu bar's dark/light mode. This is already done in `applicationDidFinishLaunching` — repeat the same two-step pattern for the active state image.

### Pattern 2: Composing Resolver for UserDefaults Path (CONF-01)

**What:** A new `VimPathResolving` struct that checks UserDefaults first, then falls back to `ShellVimPathResolver`. Fits the existing protocol injection pattern exactly.
**When to use:** Any time a custom binary path override should take precedence over PATH resolution.

```swift
// In SystemProtocols.swift — follows existing ShellVimPathResolver pattern
struct UserDefaultsVimPathResolver: VimPathResolving {
    private let fallback: VimPathResolving
    private let defaults: UserDefaults
    private let key: String

    init(
        fallback: VimPathResolving = ShellVimPathResolver(),
        defaults: UserDefaults = .standard,
        key: String = "customVimPath"
    ) {
        self.fallback = fallback
        self.defaults = defaults
        self.key = key
    }

    func resolveVimPath() -> String? {
        if let custom = defaults.string(forKey: key),
           !custom.isEmpty,
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        // D-06: invalid custom path falls back silently
        return fallback.resolveVimPath()
    }
}
```

This struct is injected into `VimSessionManager.init(vimPathResolver:)` — no changes to `VimSessionManager` itself.

### Pattern 3: NSOpenPanel for File Picker (CONF-01 D-04)

**What:** Modal file picker limited to executable files under `/usr/`, `/opt/`, and `~/` directories.
**When to use:** User clicks "Set Vim Path...".

```swift
// In MenuBarController — @MainActor context, safe to run modal panel
@objc private func setVimPath() {
    let panel = NSOpenPanel()
    panel.title = "Choose Vim Binary"
    panel.message = "Select the vim executable to use with AnyVim"
    panel.prompt = "Select"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = []  // No UTI filter — executables have no standard UTI
    panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")  // Sensible default

    // Run modal — safe because MenuBarController is @MainActor
    if panel.runModal() == .OK, let url = panel.url {
        let path = url.path
        if FileManager.default.isExecutableFile(atPath: path) {
            UserDefaults.standard.set(path, forKey: "customVimPath")
            vimPathConfigDelegate?.vimPathDidChange()  // triggers rebuildMenu
        }
        // else: silently ignore non-executable selection
    }
}
```

**NSOpenPanel notes:**
- `allowedContentTypes` filtering on macOS 13+ uses `UTType`. Executables have no standard UTI that reliably identifies them across Homebrew, system paths, etc. Setting an empty array (no filter) with a good initial `directoryURL` is the correct approach — users should know what file to pick.
- `canChooseFiles = true, canChooseDirectories = false` is the minimum correct configuration.
- `.runModal()` is synchronous and must be called on the main thread. `@MainActor` isolation on `MenuBarController` guarantees this.

### Pattern 4: Vim Path Display in Menu (CONF-01 D-05)

**What:** A disabled menu item showing the currently active vim path.
**When to use:** Every `buildMenu()` call — the item reflects live state.

```swift
// In MenuBarController.buildMenu() — vim path section
let resolvedPath = vimPathResolver.resolveVimPath() ?? "vim not found"
let isCustomSet = UserDefaults.standard.string(forKey: "customVimPath")?.isEmpty == false
let isCustomValid = isCustomSet &&
    FileManager.default.isExecutableFile(
        atPath: UserDefaults.standard.string(forKey: "customVimPath")!)

let pathDisplay: String
if isCustomSet && !isCustomValid {
    pathDisplay = "Vim: (custom path invalid)"
} else {
    pathDisplay = "Vim: \(resolvedPath)"
}
let pathItem = NSMenuItem(title: pathDisplay, action: nil, keyEquivalent: "")
pathItem.isEnabled = false
menu.addItem(pathItem)
```

**Note:** `buildMenu()` already calls live state on every invocation (no caching). The vim path display follows this same pattern — it reads UserDefaults and calls `resolveVimPath()` fresh on each menu open. This is fast enough: `isExecutableFile` is a filesystem stat call (~microseconds), and `resolveVimPath()` on the custom-path fast path returns immediately without spawning a shell process.

### Pattern 5: rebuildMenu Notification After Path Change (CONF-01)

**What:** After saving a new path in UserDefaults, trigger `AppDelegate.rebuildMenu()` so the menu reflects the change immediately on next open.
**When to use:** After "Set Vim Path..." saves and after "Reset Vim Path" clears.

The existing `rebuildMenu()` pattern requires a callback from `MenuBarController` to `AppDelegate`. Current precedent: `HotkeyManager.onHealthChange` closure triggers `rebuildMenu()` in AppDelegate. The same pattern applies here — pass a `onVimPathChange: (() -> Void)?` callback to `MenuBarController`, or access it via the vimPathConfigDelegate reference.

Simpler alternative (recommended): `MenuBarController` can accept `rebuildMenu` as an `@escaping () -> Void` closure injected at init, just like `HotkeyManager.onHealthChange`. But since `MenuBarController` is already owned by `AppDelegate`, the simplest approach is to pass a reference to `AppDelegate.rebuildMenu` at construction time or use the existing `onVimPathChange` pattern.

Alternatively, since `MenuBarController.buildMenu()` reads live state on every call and the menu is rebuilt on every open anyway (it's not cached between opens), a post-change rebuild is only needed to update the in-memory `statusItem.menu` reference. The current code already calls `rebuildMenu()` on permission changes — the same mechanism works here.

### Anti-Patterns to Avoid

- **Caching the image reference:** `NSImage.isTemplate` must be set on the image object, not once at init. A new `NSImage(systemSymbolName:)` call is required each time because assigning to `button.image` replaces the reference. Set `isTemplate = true` on the new image before assigning.
- **Running NSOpenPanel off main thread:** Always call `panel.runModal()` from `@MainActor` context. `MenuBarController` is already `@MainActor final class` — no special handling needed.
- **Storing invalid path silently without showing feedback:** D-06 requires the menu to show "(custom path invalid)" — this display check must happen in `buildMenu()` reading UserDefaults, not at set-time only.
- **Resolving vim path in buildMenu() via ShellVimPathResolver:** `ShellVimPathResolver` spawns a shell subprocess (`/bin/zsh -l -c "which vim"`). Calling this in `buildMenu()` on every menu open would block the main thread for 100-300ms. For the display item, read the custom path from UserDefaults directly or cache the last resolved path. Only call the full resolver on actual trigger.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File picker UI | Custom file path NSTextField + manual validation UI | `NSOpenPanel` | Native OS file picker handles sandboxing, bookmarks, and UI consistency |
| Binary validation | Parsing file headers or checking execute bit via POSIX | `FileManager.default.isExecutableFile(atPath:)` | Foundation handles the stat() + permissions check correctly including ACLs |
| Menu icon animation | CAAnimation or Timer-driven frame swap | Simple `button.image` reassignment | A single symbol swap is instantaneous — animation would be distracting in a menu bar context |

**Key insight:** Both MENU-02 and CONF-01 are "obvious use of existing API" problems. The entire phase is wiring, not building.

---

## Common Pitfalls

### Pitfall 1: `isTemplate` Not Set on Replacement Image
**What goes wrong:** Active-session icon appears as full-color image in the menu bar, doesn't invert on dark menu bar.
**Why it happens:** `NSImage(systemSymbolName:)` returns an image with `isTemplate = false` by default. The existing idle icon has `isTemplate = true` set explicitly. When replacing the image, the new image also needs it set.
**How to avoid:** Always set `button.image?.isTemplate = true` after assigning a new image to `statusItem.button`.
**Warning signs:** Icon looks "stuck" or wrong color in dark menu bar.

### Pitfall 2: Icon Not Restored on Early Exit Paths
**What goes wrong:** captureText fails (returns nil) → early return from handleHotkeyTrigger → icon stays in active state permanently.
**Why it happens:** Icon swap placed before the guard but restore placed only after the vim session completes.
**How to avoid:** D-03 is precise — restore happens in the `defer` block alongside `isEditSessionActive = false`. The defer block runs on ALL exit paths including the `showCaptureFailureAlert()` early return.
**Warning signs:** Menu bar icon shows active state with no vim window open.

### Pitfall 3: ShellVimPathResolver Called From buildMenu()
**What goes wrong:** Menu open causes a 100-300ms hang while `/bin/zsh -l -c "which vim"` spawns.
**Why it happens:** The vim path display item in `buildMenu()` calls the full resolver to get the displayed path.
**How to avoid:** For the display item, read `UserDefaults.standard.string(forKey: "customVimPath")` directly if custom path is set. Only fall through to the shell resolver if needed, and consider caching the last resolved PATH-based result.
**Warning signs:** Menu feels sluggish to open.

### Pitfall 4: NSOpenPanel `allowedContentTypes` Filters Out Executables
**What goes wrong:** User navigates to `/opt/homebrew/bin/vim` but the file is grayed out and unselectable.
**Why it happens:** Setting `allowedContentTypes` to `[.unixExecutable]` or similar UTI — on macOS, the UTI system does not reliably categorize Homebrew-installed binaries as executable UTIs.
**How to avoid:** Set `allowedContentTypes = []` (no content type filter). Validate after selection using `FileManager.isExecutableFile(atPath:)`.
**Warning signs:** User reports "can't select my vim binary".

### Pitfall 5: Menu Rebuild Not Triggered After Path Save
**What goes wrong:** User sets a custom vim path, the save dialog dismisses, but the menu still shows the old path info item until the app is restarted.
**Why it happens:** The path change handler only writes to UserDefaults without calling `rebuildMenu()`.
**How to avoid:** After any successful `UserDefaults.standard.set(_, forKey: "customVimPath")` or `UserDefaults.standard.removeObject(forKey: "customVimPath")`, call the rebuild callback so `statusItem.menu` is updated.

---

## Code Examples

### Existing icon setup (AppDelegate.applicationDidFinishLaunching)
```swift
// Source: Sources/AnyVim/AppDelegate.swift line 38-41
if let button = statusItem.button {
    button.image = NSImage(systemSymbolName: "character.cursor.ibeam",
                           accessibilityDescription: "AnyVim")
    button.image?.isTemplate = true
}
```

### Existing UserDefaults usage (VimSessionManager)
```swift
// Source: Sources/AnyVim/VimSessionManager.swift line 178-181
if let saved = UserDefaults.standard.string(forKey: windowFrameKey) {
    let rect = NSRectFromString(saved)
    if rect.width > 100 && rect.height > 100 {
        return rect
    }
}
```

### Existing protocol injection in VimSessionManager.init
```swift
// Source: Sources/AnyVim/VimSessionManager.swift line 79-86
init(
    vimPathResolver: VimPathResolving = ShellVimPathResolver(),
    fileModDateReader: FileModificationDateReading = SystemFileModificationDateReader(),
    showAlerts: Bool = true
) {
    self.vimPathResolver = vimPathResolver
    ...
}
```

### Existing menu item pattern (MenuBarController.buildMenu)
```swift
// Source: Sources/AnyVim/MenuBarController.swift line 35-46
if permissionManager.isAccessibilityGranted {
    let item = NSMenuItem(title: "Accessibility: Granted", action: nil, keyEquivalent: "")
    menu.addItem(item)
} else {
    let item = NSMenuItem(
        title: "Accessibility: Not Granted — Click to Enable",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
    )
    item.target = self
    menu.addItem(item)
}
```

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — all APIs are AppKit/Foundation already linked, test suite passes with `xcodebuild test`).

Test suite confirmed green: `** TEST SUCCEEDED **` (27 tests passing as of 2026-04-02).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode 16.3) |
| Config file | AnyVim.xcodeproj |
| Quick run command | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test` |
| Full suite command | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| MENU-02 | Icon changes to active symbol before captureText | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/MenuBarControllerTests` | ❌ Wave 0 |
| MENU-02 | Icon restores to idle symbol after session ends | unit | same | ❌ Wave 0 |
| MENU-02 | Icon restores on early exit (captureText failure) | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/EditCycleCoordinatorTests` | ❌ Wave 0 |
| CONF-01 | UserDefaultsVimPathResolver returns custom path when set and valid | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ Wave 0 |
| CONF-01 | UserDefaultsVimPathResolver falls back to ShellVimPathResolver when custom path invalid | unit | same | ❌ Wave 0 |
| CONF-01 | UserDefaultsVimPathResolver falls back when custom path not set | unit | same | ❌ Wave 0 |
| CONF-01 | buildMenu() shows custom path in vim info item when set | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/MenuBarControllerTests` | ❌ Wave 0 |
| CONF-01 | buildMenu() shows "(custom path invalid)" when stored path is non-executable | unit | same | ❌ Wave 0 |
| CONF-01 | Reset Vim Path clears UserDefaults key | unit | same | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild -scheme AnyVim -destination 'platform=macOS' test`
- **Per wave merge:** `xcodebuild -scheme AnyVim -destination 'platform=macOS' test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

All tests for Phase 6 behaviors are new — no existing test covers icon swapping, UserDefaultsVimPathResolver, or vim path menu items. The test files that will receive new test methods already exist:

- [ ] `AnyVimTests/MenuBarControllerTests.swift` — needs vim path section tests (CONF-01: path display, invalid path display, reset action) and icon state tests (MENU-02: icon name during/after session)
- [ ] `AnyVimTests/VimSessionManagerTests.swift` — needs `UserDefaultsVimPathResolver` unit tests (CONF-01: valid custom, invalid custom, nil custom)
- [ ] `AnyVimTests/EditCycleCoordinatorTests.swift` — needs icon-state assertions in existing trigger tests (MENU-02: icon restores on all exit paths)

Note: Icon swap tests on `AppDelegate` require access to `statusItem` — this property is currently `private var`. The plan should either expose it as `internal` for testing, or verify icon behavior indirectly via `AppDelegate.statusItem.button?.image?.accessibilityDescription`. The existing test pattern (EditCycleCoordinatorTests creates AppDelegate directly without calling `applicationDidFinishLaunching`) means `statusItem` is nil in test context. The plan must decide: mock out the icon swap (e.g., extract an `iconUpdating` protocol) or accept that icon swap is not unit-testable at the AppDelegate level and rely on integration/manual verification.

---

## Project Constraints (from CLAUDE.md)

These are the binding directives that planning and implementation MUST honor:

| Directive | Source |
|-----------|--------|
| Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY=complete` | CLAUDE.md §Language and Runtime |
| `@MainActor` isolation for all managers and AppDelegate | CLAUDE.md conventions + Phase 2 decisions |
| AppKit NSStatusItem (not SwiftUI MenuBarExtra) | CLAUDE.md §Menu Bar Integration |
| `button.image?.isTemplate = true` for dark/light adaptation | CLAUDE.md §Menu Bar Integration |
| No AXSwift (unmaintained), no AXorcist (overkill) | CLAUDE.md §Accessibility API |
| Raw AXUIElement is the standard for system interaction | CLAUDE.md §Accessibility API |
| Protocol-based testability for system API interactions | CLAUDE.md §Conventions + established codebase pattern |
| `buildMenu()` returns fresh NSMenu (no caching) | Established codebase pattern since Phase 1 |
| UserDefaults for persistence | Established codebase pattern (VimWindowFrame) |
| No heavy frameworks beyond macOS-provided APIs | CLAUDE.md §Constraints > Binary size |
| GSD workflow required before file-changing tools | CLAUDE.md §GSD Workflow Enforcement |

---

## Sources

### Primary (HIGH confidence)
- Existing codebase: `Sources/AnyVim/AppDelegate.swift` — icon setup pattern, `isEditSessionActive` defer pattern
- Existing codebase: `Sources/AnyVim/MenuBarController.swift` — `buildMenu()` fresh-state pattern, @objc action pattern
- Existing codebase: `Sources/AnyVim/SystemProtocols.swift` — `VimPathResolving`, `ShellVimPathResolver` — composing resolver pattern
- Existing codebase: `Sources/AnyVim/VimSessionManager.swift` — UserDefaults VimWindowFrame usage, injectable init pattern
- Apple Developer Documentation: `NSOpenPanel` — `canChooseFiles`, `allowedContentTypes`, `runModal()` semantics
- Apple Developer Documentation: `FileManager.isExecutableFile(atPath:)` — binary validation
- Apple Developer Documentation: `NSImage.isTemplate` — must be set explicitly on new image instances

### Secondary (MEDIUM confidence)
- CLAUDE.md §Menu Bar Integration: NSStatusItem/SF Symbols template mode guidance
- Phase 1 CONTEXT.md D-05: `character.cursor.ibeam` as the established idle symbol

### Tertiary (LOW confidence — not needed; all design is derived from codebase inspection)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are already used in this codebase; no new dependencies
- Architecture: HIGH — composing resolver and icon swap follow directly from existing patterns; no speculation required
- Pitfalls: HIGH — pitfall 1 (isTemplate) and pitfall 3 (ShellVimPathResolver in buildMenu) are directly readable from the existing code

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable AppKit/UserDefaults APIs — 30-day window appropriate)
