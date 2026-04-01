# Roadmap: AnyVim

## Overview

AnyVim is built in six phases that follow strict component dependencies. The app shell and permissions layer must exist before anything else runs, code-signing identity must be locked in before the first functional code touches TCC, and the edit cycle coordinator is the last piece — wiring together the hotkey detector, accessibility bridge, and vim launcher built in the three preceding phases. Phase 6 adds polish and configuration after the full loop is verified end-to-end.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: App Shell and Permissions** - Runnable menu bar daemon with permission onboarding and re-poll-after-grant flow
- [ ] **Phase 2: Global Hotkey Detection** - Reliable double-tap Control detection via CGEventTap with health monitoring
- [ ] **Phase 3: Accessibility Bridge and Clipboard** - Text grab and paste-back with full clipboard preservation across all exit paths
- [ ] **Phase 4: Vim Session** - Floating SwiftTerm window hosting vim, detecting :wq/:q! exit reliably
- [ ] **Phase 5: Edit Cycle Integration** - Complete trigger-grab-edit-paste loop wired with re-entrancy protection and temp file cleanup
- [ ] **Phase 6: Polish and Configuration** - Visual session indicator, configurable vim path, and documented compatibility

## Phase Details

### Phase 1: App Shell and Permissions
**Goal**: A runnable background agent exists with menu bar presence and permission onboarding that does not require app restart after permissions are granted
**Depends on**: Nothing (first phase)
**Requirements**: MENU-01, MENU-03, MENU-04, PERM-01, PERM-02, PERM-03
**Success Criteria** (what must be TRUE):
  1. App runs in the menu bar with no Dock icon and persists after the launch terminal closes
  2. App shows actionable guidance when Accessibility or Input Monitoring permission is missing
  3. After the user grants a missing permission in System Settings, the app detects it within a few seconds without requiring a restart
  4. Menu contains a functioning Quit item that terminates the process cleanly
  5. App can be configured to launch at login
**Plans:** 2/3 plans executed
Plans:
- [x] 01-01-PLAN.md — Xcode project, app shell, menu bar icon, Quit menu, test infrastructure
- [x] 01-02-PLAN.md — Permission checking, re-polling, sequential alerts, login item, notifications
- [ ] 01-03-PLAN.md — Manual smoke test of full Phase 1 flow

### Phase 2: Global Hotkey Detection
**Goal**: Double-tapping Control triggers the app reliably from any focused application without false-positives on normal keyboard use
**Depends on**: Phase 1
**Requirements**: HOTKEY-01, HOTKEY-02, HOTKEY-03
**Success Criteria** (what must be TRUE):
  1. Double-tapping Control within ~350ms fires the trigger while the user is in any application (browser, native app, terminal)
  2. Single Control taps, held Control, and Ctrl+other-key combinations do not trigger the app
  3. The event tap continues functioning after the app has been running for an extended period (no silent tap death)
**Plans:** 1/2 plans executed
Plans:
- [x] 02-01-PLAN.md — HotkeyManager with CGEventTap, double-tap state machine, tap health monitor, and unit tests
- [ ] 02-02-PLAN.md — Wire HotkeyManager into AppDelegate and MenuBarController, manual verification

### Phase 3: Accessibility Bridge and Clipboard
**Goal**: The app can grab text from any focused text field and paste edited text back, leaving the user's clipboard exactly as it was before the trigger
**Depends on**: Phase 2
**Requirements**: CAPT-01, CAPT-02, CAPT-03, CAPT-04, COMPAT-01, COMPAT-02, COMPAT-03
**Success Criteria** (what must be TRUE):
  1. Triggering in a populated text field captures the existing text correctly in native Cocoa apps (TextEdit, Notes, Mail) and browser text areas (Safari, Chrome, Firefox)
  2. Triggering in an empty text field produces an empty temp file without crashing or hanging
  3. After the edit cycle completes (or aborts), the user's original clipboard contents are identical to what they were before triggering
  4. The simulated Cmd+A / Cmd+C / Cmd+V keystrokes do not race — text is reliably captured and pasted back
**Plans**: TBD

### Phase 4: Vim Session
**Goal**: A floating terminal window opens with the user's text loaded in vim, and the app reliably detects when the user exits via :wq or :q!
**Depends on**: Phase 1
**Requirements**: VIM-01, VIM-02, VIM-03, VIM-04
**Success Criteria** (what must be TRUE):
  1. A dedicated floating terminal window opens with vim and the temp file loaded, without launching Terminal.app
  2. The user's ~/.vimrc settings are applied in the vim session
  3. Closing vim with :wq signals the app that an edit was completed
  4. Closing vim with :q! signals the app that the edit was aborted
**Plans**: TBD
**UI hint**: yes

### Phase 5: Edit Cycle Integration
**Goal**: The complete trigger-grab-edit-paste workflow functions end-to-end, handling the happy path and all abort/error paths with temp file cleanup on every exit
**Depends on**: Phases 2, 3, 4
**Requirements**: REST-01, REST-02, REST-03, REST-04, REST-05
**Success Criteria** (what must be TRUE):
  1. After :wq, the edited text appears in the original text field replacing the previous contents
  2. After :q!, the original text field is unchanged
  3. The temp file is deleted after every edit cycle, regardless of how vim exited
  4. Triggering the hotkey while an edit session is already active does nothing (no second window opens)
**Plans**: TBD

### Phase 6: Polish and Configuration
**Goal**: The app provides visual feedback during active sessions and lets the user point to a non-default vim binary
**Depends on**: Phase 5
**Requirements**: MENU-02, CONF-01
**Success Criteria** (what must be TRUE):
  1. The menu bar icon changes visually while a vim session is active and returns to its default state when the session ends
  2. The user can configure a custom vim binary path, and the app uses that binary on subsequent triggers
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6
Note: Phases 3 and 4 are independent of each other and may be planned/built in parallel.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. App Shell and Permissions | 2/3 | In Progress|  |
| 2. Global Hotkey Detection | 0/2 | Not started | - |
| 3. Accessibility Bridge and Clipboard | 0/? | Not started | - |
| 4. Vim Session | 0/? | Not started | - |
| 5. Edit Cycle Integration | 0/? | Not started | - |
| 6. Polish and Configuration | 0/? | Not started | - |
