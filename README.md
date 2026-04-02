# AnyVim

A macOS menu bar utility that lets you use vim to edit text in any text field across any application.

Double-tap the Control key to open vim with the current text field's contents, edit freely, and `:wq` to send the edited text back.

## Features

- **Works everywhere** — native Cocoa apps (TextEdit, Notes, Mail) and browser text areas (Safari, Chrome, Firefox)
- **System-wide hotkey** — double-tap Control from any application
- **Real vim** — your `~/.vimrc` is loaded, full color and cursor support via an embedded terminal
- **Clipboard preservation** — your clipboard is restored after every edit cycle
- **Lightweight** — runs as a menu bar icon with no Dock presence
- **Configurable vim path** — point to a custom vim binary via the menu bar

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 16.3+ (for building from source)
- vim (ships with macOS or install via Homebrew)

## Installation

AnyVim is currently built from source:

```bash
git clone https://github.com/Nick-Anderssohn/any-vim.git
cd any-vim
open AnyVim.xcodeproj
```

Build and run from Xcode (Cmd+R). The app must be signed with a Developer ID certificate — ad-hoc signing will not work because macOS TCC requires a stable code identity for Accessibility and Input Monitoring permissions.

On first launch, AnyVim will prompt you to grant two permissions in System Settings > Privacy & Security:

1. **Accessibility** — needed to read and write text in other apps
2. **Input Monitoring** — needed to detect the double-tap Control hotkey

AnyVim detects when permissions are granted without requiring a restart.

## Usage

1. Focus a text field in any application
2. Double-tap the Control key (within ~350ms)
3. A floating vim window appears with the text field's contents
4. Edit normally — your `~/.vimrc` applies
5. `:wq` to save — the edited text replaces the original text field contents
6. `:q!` to abort — the original text is left unchanged

The menu bar icon changes from a cursor beam to a pencil while a vim session is active.

### Menu bar options

- **Vim path** — shows the current vim binary (defaults to `vim` in your PATH)
- **Set Vim Path...** — pick a custom vim binary
- **Reset Vim Path** — revert to the default
- **Launch at Login** — toggle automatic startup
- **Quit AnyVim** — exit the app

## Development

### Building

```bash
# Open in Xcode
open AnyVim.xcodeproj

# Or build from the command line
xcodebuild build -scheme AnyVim -destination 'platform=macOS'
```

The project uses Swift Package Manager for dependencies. Xcode resolves packages automatically on first build. The only external dependency is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for the embedded terminal emulator.

### Running tests

```bash
xcodebuild test -scheme AnyVim -destination 'platform=macOS'
```

There are 67 unit tests covering permission management, hotkey detection, clipboard handling, temp file management, accessibility bridge, vim session lifecycle, edit cycle coordination, and menu bar UI.

### Project structure

```
Sources/AnyVim/
  AppDelegate.swift           # App entry point, edit cycle orchestration
  MenuBarController.swift     # Menu bar icon and dropdown menu
  PermissionManager.swift     # Accessibility & Input Monitoring permission checks
  HotkeyManager.swift         # CGEventTap double-tap Control detection
  AccessibilityBridge.swift   # Text capture (Cmd+A/C) and restore (Cmd+A/V)
  ClipboardGuard.swift        # Clipboard snapshot and restore
  TempFileManager.swift       # Temp file create/delete for vim I/O
  VimSessionManager.swift     # SwiftTerm vim session lifecycle
  VimPanel.swift              # Floating NSPanel for the vim window
  SystemProtocols.swift       # Protocols for pasteboard, keystrokes, vim path resolution
  EditCycleCoordinating.swift # Protocols for test injection
  LoginItemManager.swift      # Launch at login via SMAppService
  NotificationManager.swift   # Permission grant notifications
AnyVimTests/                  # Unit tests for all components
AnyVim/
  Info.plist                  # LSUIElement, permission usage descriptions
  AnyVim.entitlements         # Hardened runtime entitlements
```

### Code signing

AnyVim **must** be signed with a valid Developer ID or development certificate. macOS TCC ties Accessibility and Input Monitoring permissions to code identity — ad-hoc signed apps won't appear in System Settings. If you re-sign the app during development, you may need to re-grant permissions.

## License

MIT
