# Requirements: AnyVim

**Defined:** 2026-03-31
**Core Value:** Seamless vim editing in any text input on macOS — the trigger-edit-return loop must feel instant and reliable.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Hotkey

- [ ] **HOTKEY-01**: App detects double-tap of Control key system-wide via CGEventTap
- [ ] **HOTKEY-02**: Double-tap detection uses a timing threshold (~350ms) to distinguish from single taps and held modifier
- [ ] **HOTKEY-03**: Hotkey works regardless of which application is focused

### Permissions

- [x] **PERM-01**: App checks for Accessibility permission on launch and displays guidance if not granted
- [x] **PERM-02**: App checks for Input Monitoring permission on launch and displays guidance if not granted
- [x] **PERM-03**: App re-checks permission state periodically and updates status accordingly

### Text Capture

- [x] **CAPT-01**: On trigger, app saves the current clipboard contents (all pasteboard types) for later restoration
- [ ] **CAPT-02**: App sends Cmd+A, Cmd+C to the focused application via CGEvent to grab text field contents
- [x] **CAPT-03**: App reads the grabbed text from the clipboard and writes it to a temporary file
- [x] **CAPT-04**: App handles the case where the focused field is empty (empty temp file)

### Vim Session

- [ ] **VIM-01**: App opens a lightweight dedicated terminal window (not Terminal.app) with vim loaded with the temp file
- [ ] **VIM-02**: Terminal window uses SwiftTerm or equivalent for a PTY-backed vim session
- [ ] **VIM-03**: User's existing ~/.vimrc is used (vim launched normally)
- [ ] **VIM-04**: App detects vim process termination (user did :wq or :q!)

### Text Restore

- [ ] **REST-01**: On :wq, app reads the edited temp file and places contents on the clipboard
- [ ] **REST-02**: App sends Cmd+A, Cmd+V to the original application to replace text field contents
- [ ] **REST-03**: On :q!, app detects the file was not modified and skips paste-back
- [ ] **REST-04**: After paste-back (or abort), app restores the user's original clipboard contents
- [ ] **REST-05**: Temp file is deleted after the edit cycle completes

### Menu Bar

- [x] **MENU-01**: App runs as a menu bar app with a status icon (no dock icon)
- [ ] **MENU-02**: Menu bar icon animates or changes while a vim session is active
- [x] **MENU-03**: Menu includes a Quit option
- [x] **MENU-04**: App launches at login (optional, configurable)

### Configuration

- [ ] **CONF-01**: User can configure the path to the vim binary (defaults to vim in PATH)

### Compatibility

- [ ] **COMPAT-01**: App works with native Cocoa text fields (TextEdit, Notes, Mail)
- [ ] **COMPAT-02**: App works with browser text areas (Safari, Chrome, Firefox)
- [ ] **COMPAT-03**: App handles timing delays between simulated keystrokes (100-150ms between Cmd+A and Cmd+C)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Editing

- **EDIT-01**: User can start vim in insert mode via a preference
- **EDIT-02**: App keeps edit history in ~/.local/share/any-vim/ for recovery
- **EDIT-03**: File type hint via temp file extension based on context

### Compatibility

- **COMPAT-04**: Graceful Electron app support with fallback strategies
- **COMPAT-05**: Browser address bar support

### Configuration

- **CONF-02**: Custom hotkey configuration (beyond double-tap Control)
- **CONF-03**: Neovim support as an alternative editor

## Out of Scope

| Feature | Reason |
|---------|--------|
| Vim keybindings overlay (kindaVim-style) | Different product category — AnyVim launches real vim |
| Browser extension (Firenvim-style) | Extension maintenance burden; temp-file approach works across all apps |
| Plugin system / extensibility | No validated demand; premature generalization |
| Bundled vim binary | Increases binary size; users already have vim on macOS |
| App Store distribution | Accessibility + Input Monitoring permissions incompatible with sandbox |
| Multi-editor support (Emacs, nano) | Dilutes product identity; named "AnyVim" |
| Vim config management | Scope creep; vim uses ~/.vimrc automatically |
| Linux/Windows support | macOS-only APIs throughout |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOTKEY-01 | Phase 2 | Pending |
| HOTKEY-02 | Phase 2 | Pending |
| HOTKEY-03 | Phase 2 | Pending |
| PERM-01 | Phase 1 | Complete |
| PERM-02 | Phase 1 | Complete |
| PERM-03 | Phase 1 | Complete |
| CAPT-01 | Phase 3 | Complete |
| CAPT-02 | Phase 3 | Pending |
| CAPT-03 | Phase 3 | Complete |
| CAPT-04 | Phase 3 | Complete |
| VIM-01 | Phase 4 | Pending |
| VIM-02 | Phase 4 | Pending |
| VIM-03 | Phase 4 | Pending |
| VIM-04 | Phase 4 | Pending |
| REST-01 | Phase 5 | Pending |
| REST-02 | Phase 5 | Pending |
| REST-03 | Phase 5 | Pending |
| REST-04 | Phase 5 | Pending |
| REST-05 | Phase 5 | Pending |
| MENU-01 | Phase 1 | Complete |
| MENU-02 | Phase 6 | Pending |
| MENU-03 | Phase 1 | Complete |
| MENU-04 | Phase 1 | Complete |
| CONF-01 | Phase 6 | Pending |
| COMPAT-01 | Phase 3 | Pending |
| COMPAT-02 | Phase 3 | Pending |
| COMPAT-03 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 27 total
- Mapped to phases: 27
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 after roadmap creation — all 27 v1 requirements mapped*
