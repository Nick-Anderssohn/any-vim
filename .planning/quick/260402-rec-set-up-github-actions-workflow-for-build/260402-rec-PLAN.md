---
phase: quick
plan: 260402-rec
type: execute
wave: 1
depends_on: []
files_modified:
  - .github/workflows/release.yml
  - scripts/create-dmg.sh
autonomous: true
requirements: []
must_haves:
  truths:
    - "Pushing a version tag (e.g. v1.1) triggers a CI build that produces a signed, notarized .dmg"
    - "A GitHub Release is created automatically with the .dmg attached"
    - "The workflow uses secrets for certificate, Apple ID, and notarization credentials"
  artifacts:
    - path: ".github/workflows/release.yml"
      provides: "GitHub Actions release workflow"
    - path: "scripts/create-dmg.sh"
      provides: "DMG creation script with drag-to-Applications layout"
  key_links:
    - from: ".github/workflows/release.yml"
      to: "scripts/create-dmg.sh"
      via: "bash invocation during build"
      pattern: "scripts/create-dmg"
---

<objective>
Create a GitHub Actions workflow that builds, signs, notarizes, and releases AnyVim when a version tag is pushed.

Purpose: Automate the entire release pipeline so pushing a tag like `v1.1` produces a signed, notarized .dmg attached to a GitHub Release — no manual steps.
Output: `.github/workflows/release.yml` and `scripts/create-dmg.sh`
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/quick/260402-rec-set-up-github-actions-workflow-for-build/260402-rec-CONTEXT.md
@AnyVim/AnyVim.entitlements
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create DMG packaging script</name>
  <files>scripts/create-dmg.sh</files>
  <action>
Create `scripts/create-dmg.sh` — a bash script that takes two arguments: the path to AnyVim.app and the output .dmg path.

The script must:
1. Create a temporary directory with the .app bundle and a symlink to /Applications
2. Use `hdiutil create` to produce a compressed .dmg from that directory
3. Clean up the temporary directory
4. Exit non-zero on any failure (use `set -euo pipefail`)

Keep it simple — use `hdiutil` directly (no `create-dmg` npm package needed). The layout is standard drag-to-Applications.

Make the script executable (`chmod +x`).
  </action>
  <verify>
    <automated>bash -n /Users/nick/Projects/any-vim/scripts/create-dmg.sh && test -x /Users/nick/Projects/any-vim/scripts/create-dmg.sh && echo "OK"</automated>
  </verify>
  <done>Script exists, is executable, passes bash syntax check</done>
</task>

<task type="auto">
  <name>Task 2: Create GitHub Actions release workflow</name>
  <files>.github/workflows/release.yml</files>
  <action>
Create `.github/workflows/release.yml` triggered on tag push matching `v*`.

The workflow has a single job `build-sign-notarize-release` running on `macos-15`:

**Step 1 — Checkout:**
- `actions/checkout@v4`

**Step 2 — Select Xcode:**
- Use `sudo xcode-select -s /Applications/Xcode_16.3.app` (macOS 15 runners ship with Xcode 16.x)

**Step 3 — Import signing certificate:**
- Decode `${{ secrets.CERTIFICATE_P12 }}` (base64) to a .p12 file
- Create a temporary keychain (`build.keychain`), set it as default and add to search list
- Import the .p12 using `security import` with `-T /usr/bin/codesign`
- Set keychain partition list to allow codesign access: `security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" build.keychain`
- Use a random keychain password generated via `uuidgen`

**Step 4 — Resolve SPM dependencies:**
- `xcodebuild -resolvePackageDependencies -project AnyVim.xcodeproj -scheme AnyVim`

**Step 5 — Build archive:**
```
xcodebuild archive \
  -project AnyVim.xcodeproj \
  -scheme AnyVim \
  -configuration Release \
  -archivePath $RUNNER_TEMP/AnyVim.xcarchive \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=758YPU2N3M \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--keychain build.keychain"
```

**Step 6 — Export archive:**
- Create an `ExportOptions.plist` inline with method `developer-id`, teamID `758YPU2N3M`, signing style `manual`, signing certificate `Developer ID Application`
- Run `xcodebuild -exportArchive` with the plist to produce AnyVim.app

**Step 7 — Notarize:**
- Use `xcrun notarytool submit` with `--apple-id "${{ secrets.APPLE_ID }}" --team-id "${{ secrets.APPLE_TEAM_ID }}" --password "${{ secrets.APP_SPECIFIC_PASSWORD }}"` --wait
- Submit the .app as a zip (create zip first with `ditto -c -k`)
- After notarization succeeds, run `xcrun stapler staple` on the .app

**Step 8 — Create DMG:**
- Run `bash scripts/create-dmg.sh path/to/AnyVim.app $RUNNER_TEMP/AnyVim.dmg`

**Step 9 — Create GitHub Release:**
- Use `softprops/action-gh-release@v2` with `files: ${{ runner.temp }}/AnyVim.dmg`
- `generate_release_notes: true` for automatic changelog from commits

**Step 10 — Cleanup keychain:**
- `if: always()` step that deletes the build keychain

**Secrets required (document in a comment at top of file):**
- `CERTIFICATE_P12` — base64-encoded .p12 Developer ID certificate
- `CERTIFICATE_PASSWORD` — password for the .p12
- `APPLE_ID` — Apple ID email for notarization
- `APPLE_TEAM_ID` — Apple Developer Team ID
- `APP_SPECIFIC_PASSWORD` — app-specific password for notarization

Use environment variables to avoid repeating secrets references. Keep the YAML clean with descriptive step names.
  </action>
  <verify>
    <automated>python3 -c "import yaml; yaml.safe_load(open('/Users/nick/Projects/any-vim/.github/workflows/release.yml'))" && echo "Valid YAML"</automated>
  </verify>
  <done>Workflow YAML is valid, triggers on v* tags, contains all 10 steps (checkout, xcode-select, import cert, resolve deps, archive, export, notarize, create dmg, release, cleanup)</done>
</task>

</tasks>

<verification>
- `release.yml` is valid YAML
- `create-dmg.sh` passes bash syntax check and is executable
- Workflow triggers only on `v*` tag pushes
- All 5 required secrets are referenced in the workflow
- Notarization step uses `--wait` flag
- Keychain cleanup runs with `if: always()`
</verification>

<success_criteria>
- `.github/workflows/release.yml` exists and is valid
- `scripts/create-dmg.sh` exists and is executable
- Pushing a `v*` tag would trigger the full build-sign-notarize-release pipeline
- The workflow produces a .dmg attached to a GitHub Release
</success_criteria>

<output>
After completion, create `.planning/quick/260402-rec-set-up-github-actions-workflow-for-build/260402-rec-SUMMARY.md`
</output>
