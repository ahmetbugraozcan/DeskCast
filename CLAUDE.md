# CLAUDE.md

Guidance for Claude Code when working in this repo. See [AGENTS.md](AGENTS.md) for the detailed editing rules and review checklist — this file complements it with the concrete architecture map. When they conflict, AGENTS.md wins.

## What this is

A macOS menu-bar utility toolbox. It bundles several small productivity tools behind a single `MenuBarExtra`:

- **Capture Selected Area** — `screencapture`-based region capture into a floating shelf.
- **Capture OCR** — capture a region and copy recognized text (Vision).
- **Copy Finder Path** — copy the front Finder window's path via AppleScript.
- **Search Images** — index and search local images by filename + recognized text.
- **Drop Shelf** — a floating shelf that collects dragged files/folders/links/text/images to send together.

### Naming (important)

The app is **DeskCast**. A few names differ, don't "fix" them blindly:
- User-facing name (display name, `CFBundleName`, `PRODUCT_NAME` → `DeskCast.app`) = `DeskCast`; also `AppConstants.appName = "DeskCast"` and the localized `app.name` key.
- Xcode **target and scheme are still `screenshotapp`** (internal), and the bundle identifier is still `com.ahmetbugraozcan.screenshotapp` — these are deliberately left unchanged.
- User-facing display name is read from the localized `app.name` key via `AppConstants.displayName`, not the constant.

## App shape

- SwiftUI `App` + AppKit. Entry point [DeskCastApp.swift](screenshotapp/App/DeskCastApp.swift) declares the `MenuBarExtra`, a `Settings` scene, and an `"image-search"` `Window`.
- No `LSUIElement`; `AppDelegate` sets `.accessory` in `applicationWillFinishLaunching` — no Dock icon, still Spotlight/Raycast-searchable, keeps running with no windows open.
- Only SPM dependency: `KeyboardShortcuts` 2.4.0 (do not change `Package.resolved` for non-dependency work).

## Directory layout (feature-module MVVM)

The Xcode target uses `PBXFileSystemSynchronizedRootGroup`, so moving/adding `.swift` files under `screenshotapp/` needs **no `project.pbxproj` edits**. Keep `Assets.xcassets`, `*.lproj`, and `screenshotapp.entitlements` at the target root.

- `App/` — `@main DeskCastApp`, `AppDelegate`, and `AppEnvironment` (the composition root that builds view models, injects dependencies, and owns the presentation coordinators — no singletons).
- `Core/` — cross-cutting: `Localization/` (`AppLocalization`, `AppLanguage`), `UI/` (`ToastPanelController`), `Support/` (`AppConstants`, `TemporaryPNGWriter`, extensions), and `ShelfCollecting` (cross-feature protocol).
- `Features/<Feature>/` — one folder per feature (`ScreenshotShelf`, `DropShelf`, `ImageSearch`, `Permissions`, `Settings`, `Toolbox`), each split into `Model/`, `ViewModel/`, `View/`, `Service/`, `Presentation/`.
- `en.lproj/` + `tr.lproj/` — `Localizable.strings`.

## MVVM roles

- **`*ViewModel`** — `@MainActor ObservableObject` state + orchestration. They depend on **service protocols** (injected), and drive AppKit panels through `*Presenting` protocols via a `weak var presenter` — they do **not** construct `NSPanel`.
- **Services** — OS integrations behind protocols (`ScreenshotCapturing`, `TextRecognizing`, `ScreenshotExporting`, `FinderPathProviding`, `DropShelfExporting`); concrete types are instances built in `AppEnvironment`. Permission services (`PrivacyPermissionService`, `ScreenRecordingPermissionService`) stay static OS gateways.
- **Presentation coordinators** (`*PanelCoordinator`) — own the `NSPanel` lifecycle, retained by `AppEnvironment`.

## Two settings systems — keep them in sync

Each feature threads a value through **all** of these; when you add or change a tool/setting, update every step or the UI silently drifts:

1. Model enum + `default*` constants + `Keys` (e.g. `ToolboxSettings` in `ToolboxTool.swift`).
2. `registerDefaults(defaults:)` — every key must appear in `defaultValues`.
3. `@AppStorage` use sites (menu in `DeskCastApp.swift`, `SettingsView`).
4. Menu-visibility logic — a tool shows only when `enabled && showInMenu` (see the `shouldShow*InMenu` computed vars). Disabled tools must never remain visible via `showInMenu`; `resetTools` enforces `enabled && showInMenu`.

There are three settings namespaces: `ToolboxSettings` (which tools/layout/language), `ScreenshotShelfSettings`, and `DropShelfSettings`. All three call `registerDefaults()` at launch (in `AppEnvironment`) and again inside their view models.

## Localization

- All user-facing strings go through `AppLocalization.string(_:)` / `.formatted(_:_:)`, keyed by `Localizable.strings`. English is the fallback/base language.
- `AppLocalization` reads the chosen language from the `app.language` default and loads the matching `.lproj` bundle manually, so it works even though the app forces a locale via `.environment(\.locale, selectedLanguage.locale)` on every scene.
- Add new keys to **both** `en.lproj` and `tr.lproj/Localizable.strings`.

## Concurrency rules

- Stores are `@MainActor`. Background OCR/capture/indexing must hop back to main before touching `@Published` state, the pasteboard, panels, or views.
- Watch task cancellation and expiration/auto-hide timers: cancel timers when items are removed, pinned, cleared, or trimmed (see `expirationTimers` in `ScreenshotShelfViewModel`).
- Preserve pasteboard snapshot/restore in capture paths (`ScreenshotCaptureService`).

## Permissions

Entitlements grant Apple Events (`com.apple.security.automation.apple-events`) and user-selected read-write files only. Features depend on **Screen Recording** (capture/OCR) and **Automation → Finder** (copy path). Preserve the permission-denied → alert/toast flows (`PrivacyPermissionService`, `ScreenRecordingPermissionService`, `PermissionAlertPresenter`).

## Build & test

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -configuration Debug -destination 'platform=macOS' build
```

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -destination 'platform=macOS' test
```

Tests include placeholder Swift Testing units + XCTest UI tests that launch the accessory app. Before treating a UI-test failure as a regression, check whether it's just app launch/termination flakiness from the menu-bar/accessory activation.
