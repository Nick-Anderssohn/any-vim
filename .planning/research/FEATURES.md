# Feature Landscape

**Domain:** macOS system-wide "edit in vim" utility (vim-anywhere style)
**Researched:** 2026-03-31
**Confidence:** HIGH (multiple primary sources: existing tools, GitHub issues, HN discussion)

## Ecosystem Overview

The "vim-anywhere" space has several distinct tool categories:

1. **Edit-in-vim utilities** (AnyVim's category): Grab text from a field, open real vim, write back. Examples: vim-anywhere (cknadler), osx-vimr-anywhere.
2. **Vim-mode-everywhere overlays**: Add vim keybindings to all text fields without launching vim itself. Examples: kindaVim, SketchyVim, ti-vim.
3. **Browser-only vim embeds**: Firenvim, Wasavi — embed neovim/vim inside browser textareas only.

AnyVim competes in category 1 only. Categories 2 and 3 are not substitutes — they solve a different problem (keybindings vs. the full editor).

---

## Table Stakes

Features users expect. Missing = product feels incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Global hotkey trigger | Core mechanic — no hotkey, no product | Low | Double-tap Control per PROJECT.md. Must work in all apps including Electron, browsers, native Cocoa. |
| Grab existing text from focused field | Users expect their current text to be pre-loaded in vim | Medium | Requires Cmd+A, Cmd+C via Accessibility API. Fails in some non-standard fields. |
| Write back on :wq | Core contract — `:wq` must send text back | Medium | Temp file polling or file watcher after vim process exits. |
| Clipboard restoration | Users' clipboard should survive the edit cycle | Low | Save clipboard before Cmd+C, restore after Cmd+V. Well-established pattern. Explicitly requested in vim-anywhere issue #61. |
| Works in browsers | Most users want this for web forms, GitHub PRs, email | Medium | Accessibility API varies; Chrome/Firefox generally work via standard text area AXUIElement access. |
| Works in native Cocoa apps | Notes, Mail, TextEdit, Xcode — all standard text fields | Low | AXUIElement well-supported in native Cocoa fields. |
| Menu bar presence | Background utility pattern on macOS — users expect a status icon | Low | Standard NSStatusItem in AppKit. |
| Permission prompts with guidance | Accessibility + Input Monitoring permissions are required and surprising | Low | Must detect missing permissions and direct users to System Preferences. |
| Uses user's existing ~/.vimrc | Users want their vim config, not a sandboxed vim | Low | Just launch `/usr/bin/vim` or the user's installed vim — it picks up vimrc automatically. |
| No crash on :q! (discard) | User must be able to abort without writing back | Low | Check whether temp file was modified; if unmodified, skip paste-back. |
| Temp file cleanup | No leftover files in /tmp — basic hygiene | Low | Delete temp file after paste-back (or on abort). vim-anywhere has a security issue here (issue #81) — worth doing better. |

---

## Differentiators

Features that set a product apart. Not universally expected, but valued by the target audience.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Lightweight dedicated terminal window | Launches faster than Terminal.app, no tabs/chrome, feels purpose-built | High | Custom NSWindow with embedded terminal emulator (libvterm or similar) vs. shelling out to Terminal.app. Major UX differentiator — vim-anywhere uses MacVim (heavy GUI), not terminal vim. |
| Start in insert mode option | Power users often want to start typing immediately, not navigate | Low | Launch vim with `+startinsert` flag. Requested in vim-anywhere issue #94. |
| File type hint via temp file extension | Syntax highlighting for the content type being edited | Low-Medium | Name temp file `.md` when triggered from a known markdown context (e.g., GitHub PR body). Detection logic is the complex part. |
| Edit history (temp file persistence) | Re-access recent edits if the paste-back failed or you need to recover | Low | Keep temp files in `~/.local/share/any-vim/history/` instead of /tmp. vim-anywhere does this until reboot. |
| Visual indicator during edit session | Shows the user that AnyVim is "active" and waiting | Low | Animate/change menu bar icon while vim is open. |
| Graceful Electron app support | Electron apps (Slack, VS Code, Discord) don't fully expose Accessibility API | High | Requires fallback strategy — clipboard-based inject without Cmd+A/Cmd+C grabbing, or synthesized keystrokes. Complex. |
| Works in browser address bar | Edge case but requested; vim-anywhere users report this is missing | Medium | Address bar is an AXTextField but focus/refocus behavior is finicky. |
| Configurable editor path | Let users point to a specific vim binary (e.g., Homebrew vim instead of /usr/bin/vim) | Low | Preference in menu bar app. Useful if user's .vimrc requires a newer vim. |

---

## Anti-Features

Features to explicitly NOT build for v1 (and likely beyond).

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Neovim support | Adds significant complexity (different binary, different process model, LSP startup overhead). PROJECT.md explicitly excludes this. | Ship vim only. Users who want neovim can request it post-v1. |
| Custom keybinding configuration | Every config surface adds code, tests, and support burden. The double-tap Control is a good default. | Hardcode for v1. The mechanism for changing it exists (NSUserDefaults + preferences pane) but defer it. |
| Vim keybindings overlay (kindaVim-style) | Totally different product category. Much harder (you're reimplementing vim's state machine). | You are building an "open real vim" tool, not a keybinding emulator. |
| Firenvim-style browser extension | Requires maintaining a browser extension per browser, browser extension API churn is high, and it only works in browsers. | The temp-file approach works across all apps including browsers. |
| Plugin system / extensibility | Premature generalization. No clear user demand in v1 scope. | Use hooks (e.g., run a user script on trigger) only if demand is validated post-v1. |
| Bundled vim binary | Increases binary size, creates update burden, and users already have vim on macOS. | Detect vim at `/usr/bin/vim` and user's PATH. Fail with a clear message if not found. |
| App Store distribution | Accessibility + Input Monitoring permissions are incompatible with App Store sandbox requirements. | Distribute as a direct download (.dmg or Homebrew cask). |
| Multi-editor support (Emacs, nano, etc.) | Dilutes the product identity and increases surface area. | Named "AnyVim" — commit to vim. |
| Vim config management | Managing users' ~/.vimrc is scope creep with no clear win. | Launch vim normally — it uses the user's config automatically. |
| Sync / cloud features | No user demand in this tool category. | Not applicable. |

---

## Feature Dependencies

```
Global hotkey trigger
  └── Grab existing text (requires focused-element detection first)
        └── Write to temp file
              └── Launch vim with temp file
                    └── Detect vim exit
                          └── Read temp file
                                └── Paste back to field
                                      └── Clipboard restoration (bookend: save before grab, restore after paste)
                                            └── Temp file cleanup

Permission handling
  └── Accessibility permission (required for field grab + paste back)
  └── Input Monitoring permission (required for global hotkey)
  (Both must be granted before any core flow works)

Menu bar presence
  └── Visual indicator during edit session (extends menu bar feature)
  └── Configurable editor path (extends menu bar preferences)

Lightweight terminal window
  └── Start in insert mode option (flag passed at launch time, no dependency)
  └── File type hint (only relevant if terminal window is custom — extension on temp file works regardless)
```

---

## MVP Recommendation

Prioritize:

1. Global double-tap Control hotkey (Input Monitoring permission flow)
2. Accessibility permission detection and onboarding
3. Grab text from focused field (Cmd+A, Cmd+C)
4. Write to temp file, launch terminal vim, watch for exit
5. Read temp file, paste back (Cmd+A, Cmd+V)
6. Clipboard restoration (save/restore around the Cmd+C/Cmd+V pair)
7. Temp file cleanup
8. Menu bar icon + quit menu item

Defer:
- Lightweight custom terminal window: High complexity, Terminal.app launch is functional if ugly. Validate user need first.
- File type hint: Low complexity but requires detection logic — defer until field types are better understood.
- Edit history: Low complexity but not blocking any user workflow. Add post-v1.
- Electron/browser fallbacks: High complexity, high breakage risk. Validate demand before building.

---

## Confidence Notes

| Claim | Confidence | Source |
|-------|------------|--------|
| vim-anywhere core flow (trigger, grab, edit, paste-back) is table stakes | HIGH | GitHub source, HN discussion, multiple forks |
| Clipboard restoration is expected | HIGH | vim-anywhere issue #61 explicitly requested; basic UX hygiene |
| Users want text pre-loaded from field | HIGH | vim-anywhere issue #78, HN comments |
| Lightweight terminal window is a differentiator | MEDIUM | Inferred from complaints about MacVim being heavy; no direct feature request for "lighter terminal" |
| Electron support is hard and requested | MEDIUM | SketchyVim docs, kindaVim docs both call out Electron limitations |
| File type hinting is valued | LOW | Inferred from general vim-anywhere UX patterns; no direct user request found |

---

## Sources

- [vim-anywhere (cknadler) — GitHub](https://github.com/cknadler/vim-anywhere)
- [vim-anywhere open issues — feature requests and bugs](https://github.com/cknadler/vim-anywhere/issues)
- [Vim Anywhere — Hacker News discussion](https://news.ycombinator.com/item?id=16395379)
- [SketchyVim — GitHub](https://github.com/FelixKratz/SketchyVim)
- [kindaVim — official site](https://kindavim.app/)
- [All the ways to use Vim outside of Vim on macOS — Medium](https://medium.com/@aplaceofmind/all-the-ways-you-can-use-vim-outside-of-vim-on-macos-334d4b082f0b)
- [Firenvim — GitHub](https://github.com/glacambre/firenvim)
