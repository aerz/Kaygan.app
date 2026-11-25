# AGENTS.md

## Project

Kaygan is a macOS 15+ menu-bar app for mouse scrolling and side-button navigation. It uses SwiftUI, Swift 6, Xcode 27, and XcodeGen. The generated Xcode project is not tracked.

## Commands

```sh
xcodegen generate
xcodebuild -project Kaygan.xcodeproj -scheme Kaygan build
xcodebuild -project Kaygan.xcodeproj -scheme Kaygan test
```

CI runs the same tests unsigned on arm64; see `.github/workflows/package.yml`.

## Architecture

- `Kaygan/App` — app entry point and lifecycle.
- `Kaygan/Features/Scrolling` — scroll event handling.
- `Kaygan/Features/Navigation` — Back/Forward menu commands and swipe fallback.
- `Kaygan/Settings` — settings models, UI, and button-test state.
- `KayganTests` — Swift Testing unit tests.

`project.yml` is the source of truth for targets, versions, and build settings.

## Conventions

- Run `xcodegen generate` after editing `project.yml`.
- Never commit `Kaygan.xcodeproj` or `Config/Signing.local.xcconfig`.
- Copy `Config/Signing.local.xcconfig.example` for local signing.
- Keep the bundle identifier, signing identity, and `build/Debug` path stable; Accessibility permission depends on them.
- Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
- Keep feature logic out of views and UI/AppKit work on the main actor.

## Testing

Use Swift Testing in `KayganTests`. Run the full suite before committing and add tests for changed behavior.

## Release

Push `main` to `release`:

```sh
git push origin main:release
```

The workflow runs tests, signs the app with the release certificate, and uploads the arm64 DMG plus `SHA256SUMS`. Reuse the same self-signed certificate across releases. Create the GitHub release manually after verifying the checksum and confirming Accessibility access survives replacement.
