# AGENTS.md

## Repo Shape

- This is a macOS Xcode project: `screenshotapp.xcodeproj`, scheme `screenshotapp`, product name `DeskCast`.
- App sources live in `screenshotapp/`; unit tests live in `screenshotappTests/`; UI tests live in `screenshotappUITests/`.
- The app target uses SwiftUI plus AppKit. The entry point defines a `MenuBarExtra`, `Settings`, and an `"Image Search"` window in `screenshotapp/screenshotappApp.swift`.
- The app is configured as an LSUIElement/accessory app (`LSUIElement = YES` in the project file and `.accessory` activation policy in `AppDelegate`).
- The only Swift package dependency currently pinned in `Package.resolved` is `KeyboardShortcuts` 2.4.0.

## Commands

- Build: `xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -configuration Debug -destination 'platform=macOS' build`
- Test: `xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -destination 'platform=macOS' test`
- The test command includes placeholder Swift Testing unit tests and XCTest UI tests. UI tests launch an accessory/menu-bar app, so app launch and termination behavior is a real risk when changing tests or app activation.

## Editing Rules

- Prefer minimal, localized changes inside the existing folders:
  - `Models/` defines settings enums/defaults, tool IDs, export naming, and image-search value types.
  - `Stores/` owns observable app state and coordinates services/controllers; current stores are `@MainActor`.
  - `Services/` wraps OS integrations: `screencapture`, pasteboard, Vision OCR, Finder AppleScript, permissions, and export panels.
  - `Views/` contains SwiftUI UI plus AppKit bridge/controller code.
  - `Support/` contains small shared AppKit and helper extensions.
- When adding or changing a setting/tool, update the full existing chain together: model enum/defaults, `UserDefaults.register(defaults:)`, `@AppStorage` use sites, settings UI, and menu visibility logic.
- Keep UI/state mutations on the main actor. Background OCR/capture/indexing work should return to main before touching `@Published` state, pasteboard UI, panels, or SwiftUI views.
- Preserve pasteboard restoration behavior in screenshot capture paths; `ScreenshotCaptureService` intentionally snapshots and restores the pasteboard when requested.
- Preserve OS permission handling around screen recording and Finder automation. The entitlements include Apple Events and user-selected read/write file access.
- For shelf layout or reordering changes, check both horizontal and vertical stack paths. `ScreenshotShelfPanelController` sizes/positions the panel using static constants from `ScreenshotShelfView`.
- Do not edit `Package.resolved` or `screenshotapp.xcodeproj/project.pbxproj` unless the change is actually about dependencies, targets, signing, entitlements, or build settings.

## Review Checklist

- Build with the command above after Swift or project changes.
- If running tests, note whether failures come from placeholder UI launch/termination tests before treating them as product regressions.
- Verify changed `@AppStorage` keys have defaults registered and invalid numeric values are clamped.
- For tool visibility changes, verify disabled tools cannot remain visible via `showInMenu`.
- For capture/OCR/Finder changes, check cancellation, permission-denied behavior, pasteboard contents, and user-facing alerts/toasts.
- For auto-hide or shelf mutations, check expiration timers are canceled when items are removed, pinned, cleared, or trimmed.
- For image search indexing, check task cancellation and that folder scanning/OCR does not mutate store state off the main actor.
