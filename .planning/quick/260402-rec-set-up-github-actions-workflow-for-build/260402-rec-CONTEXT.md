# Quick Task 260402-rec: Set up GitHub Actions workflow for build, sign, notarize, and release - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Task Boundary

Set up a GitHub Actions workflow that builds AnyVim, signs it with a Developer ID certificate, notarizes it with Apple, and creates a GitHub Release with a .dmg artifact when a version tag is pushed.

</domain>

<decisions>
## Implementation Decisions

### Signing secrets
- Export .p12 certificate as base64, store in GitHub Actions secrets (CERTIFICATE_P12, CERTIFICATE_PASSWORD)
- Workflow decodes base64 and imports to a temporary keychain during build
- Apple ID credentials for notarization stored as secrets (APPLE_ID, APPLE_TEAM_ID, APP_SPECIFIC_PASSWORD or NOTARY_KEY)

### Release trigger
- Tag push only (e.g., pushing v1.1 triggers the workflow)
- No manual dispatch — keep it simple and conventional
- Workflow creates a GitHub Release automatically with the built .dmg attached

### Build artifact format
- .dmg with drag-to-Applications layout
- Use create-dmg or hdiutil to produce a polished install experience
- Single artifact attached to the GitHub Release

</decisions>

<specifics>
## Specific Ideas

- The Xcode project is at `AnyVim.xcodeproj` with scheme `AnyVim`
- macOS deployment target is 13.0
- Only external dependency is SwiftTerm (SPM, resolved by Xcode)
- Development team ID is hardcoded in pbxproj (758YPU2N3M) — CI must match this signing identity
- App requires hardened runtime (entitlements file exists at AnyVim/AnyVim.entitlements)

</specifics>
