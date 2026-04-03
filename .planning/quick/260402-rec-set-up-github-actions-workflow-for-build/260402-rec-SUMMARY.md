---
phase: quick
plan: 260402-rec
subsystem: ci-cd
tags: [github-actions, release, code-signing, notarization, dmg]
dependency_graph:
  requires: []
  provides: [release-automation]
  affects: [deployment]
tech_stack:
  added: [github-actions, hdiutil, xcrun-notarytool, softprops/action-gh-release@v2]
  patterns: [tag-triggered-release, temporary-keychain-for-signing]
key_files:
  created:
    - .github/workflows/release.yml
    - scripts/create-dmg.sh
  modified: []
decisions:
  - Used hdiutil directly (no npm create-dmg) for minimal tooling deps
  - Keychain password generated from run_id + run_attempt for uniqueness
  - Notarize the .app as a zip, then staple before creating the DMG
  - softprops/action-gh-release@v2 for automatic release creation with changelog
metrics:
  duration: ~5 minutes
  completed: "2026-04-03T02:51:47Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Quick Task 260402-rec: Set Up GitHub Actions Workflow for Build Summary

**One-liner:** Tag-triggered CI pipeline using xcodebuild archive + xcrun notarytool + hdiutil DMG creation + softprops/action-gh-release for fully automated Developer ID signed and notarized releases.

## Objective

Automate the entire release pipeline so pushing a tag like `v1.1` produces a signed, notarized .dmg attached to a GitHub Release — no manual steps.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create DMG packaging script | 9445144 | scripts/create-dmg.sh |
| 2 | Create GitHub Actions release workflow | 45e0ab2 | .github/workflows/release.yml |

## What Was Built

### scripts/create-dmg.sh

A bash script with `set -euo pipefail` that:
- Accepts `<path-to-AnyVim.app>` and `<output.dmg>` as arguments
- Creates a temporary staging directory with the .app and a symlink to /Applications
- Runs `hdiutil create` with UDZO compression to produce the .dmg
- Cleans up the staging directory via a `trap cleanup EXIT` handler

### .github/workflows/release.yml

A 10-step GitHub Actions workflow triggered on `v*` tag pushes, running on `macos-15`:

1. **Checkout** — `actions/checkout@v4`
2. **Select Xcode 16.3** — pins the Xcode version used for the build
3. **Import signing certificate** — decodes base64 CERTIFICATE_P12 secret, creates a temporary `build.keychain`, imports with `-T /usr/bin/codesign`, sets partition list for codesign access
4. **Resolve SPM dependencies** — `xcodebuild -resolvePackageDependencies`
5. **Build archive** — `xcodebuild archive` with `CODE_SIGN_STYLE=Manual`, team `758YPU2N3M`, signing to `build.keychain`
6. **Export archive** — inline `ExportOptions.plist` with `method: developer-id`
7. **Notarize and staple** — `ditto` zip, `xcrun notarytool submit --wait`, `xcrun stapler staple`
8. **Create DMG** — `bash scripts/create-dmg.sh`
9. **Create GitHub Release** — `softprops/action-gh-release@v2` with `generate_release_notes: true`
10. **Clean up keychain** — `security delete-keychain` with `if: always()`

## Required Secrets

All five secrets documented in a comment at the top of `release.yml`:

| Secret | Purpose |
|--------|---------|
| `CERTIFICATE_P12` | base64-encoded Developer ID Application .p12 |
| `CERTIFICATE_PASSWORD` | Password protecting the .p12 |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APP_SPECIFIC_PASSWORD` | App-specific password for notarization |

## Verification Results

- `create-dmg.sh`: passes `bash -n` syntax check, is executable
- `release.yml`: valid YAML (pyyaml parse succeeds)
- Trigger: `on.push.tags: ['v*']`
- All 5 secrets referenced in the workflow
- Notarization uses `--wait` flag
- Keychain cleanup uses `if: always()`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — the workflow is complete. Secrets must be configured in GitHub repository settings before the workflow runs successfully.

## Self-Check: PASSED

- scripts/create-dmg.sh exists and is executable
- .github/workflows/release.yml exists and is valid YAML
- Commit 9445144 exists (create-dmg.sh)
- Commit 45e0ab2 exists (release.yml)
