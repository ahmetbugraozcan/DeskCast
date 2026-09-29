# CLAUDE.md

Guidance for Claude Code when working in this repo. See [AGENTS.md](AGENTS.md) for the detailed editing rules and review checklist — this file complements it with the concrete architecture map. When they conflict, AGENTS.md wins.

## What this is

A macOS menu-bar utility toolbox. It bundles several small productivity tools behind a single `MenuBarExtra`:

- **Capture Selected Area** — `screencapture`-based region capture into a floating media shelf. Image captures can be annotated (`Features/Annotation`: arrow, rectangle, pen, text, highlight, pixelate; Done replaces the shelf image and rewrites its saved PNG) or pinned on screen as always-on-top panels.
- **Capture Video** — full-display or resizable selected-area recording through ScreenCaptureKit and DeskCast's own recorder panel, with system-audio/microphone options. Completed videos join screenshots in the same shelf, where "Trim or Make GIF…" (`Features/VideoEditing`) saves a passthrough-trimmed copy (added to the shelf) or a looping GIF next to the original, which is never overwritten.
- **Capture OCR** — capture a region and copy recognized text, or the contents of QR codes/barcodes in it (Vision).
- **Pick Color** — system loupe (`NSColorSampler`, no Screen Recording permission) copies the picked color as HEX/RGB/HSL/SwiftUI; the last 8 colors show in the menu panel.
- **Copy Finder Path** — copy the front Finder window's path via AppleScript.
- **Search Images** — index and search local images by filename + recognized text.
- **Drop Shelf** — a floating shelf that collects dragged files/folders/links/text/images to send together.
- **Dynamic Island** — a notch-anchored panel showing the playing song (Music/Spotify), media controls, other apps' notifications, DeskCast toasts, and battery alerts; expands on hover.

### Naming (important)

The app is **DeskCast**. A few names differ, don't "fix" them blindly:
- User-facing name (display name, `CFBundleName`, `PRODUCT_NAME` → `DeskCast.app`) = `DeskCast`; also `AppConstants.appName = "DeskCast"` and the localized `app.name` key.
- Xcode **target and scheme are still `screenshotapp`** (internal), and the bundle identifier is still `com.ahmetbugraozcan.screenshotapp` — these are deliberately left unchanged.
- User-facing display name is read from the localized `app.name` key via `AppConstants.displayName`, not the constant.

## App shape

- SwiftUI `App` + AppKit. Entry point [DeskCastApp.swift](screenshotapp/App/DeskCastApp.swift) declares two `MenuBarExtra` scenes (only one inserted, by `toolbox.menuLayout`): the default `.window`-style `MenuBarPanelView` (tool tiles, now playing, recent captures, Drop Shelf) and the classic Expanded/Grouped `NSMenu`; plus a `Settings` scene and an `"image-search"` `Window`.
- No `LSUIElement`; `AppDelegate` sets `.accessory` in `applicationWillFinishLaunching` — no Dock icon, still Spotlight/Raycast-searchable, keeps running with no windows open.
- Only SPM dependency: `KeyboardShortcuts` 2.4.0 (do not change `Package.resolved` for non-dependency work).

## Directory layout (feature-module MVVM)

The Xcode target uses `PBXFileSystemSynchronizedRootGroup`, so moving/adding `.swift` files under `screenshotapp/` needs **no `project.pbxproj` edits**. Keep `Assets.xcassets`, `*.lproj`, and `screenshotapp.entitlements` at the target root.

- `App/` — `@main DeskCastApp`, `AppDelegate`, and `AppEnvironment` (the composition root that builds view models, injects dependencies, and owns the presentation coordinators — no singletons).
- `Core/` — cross-cutting: `Localization/` (`AppLocalization`, `AppLanguage`), `UI/` (`ToastPanelController`), `Support/` (`AppConstants`, `TemporaryPNGWriter`, extensions), and `ShelfCollecting` (cross-feature protocol).
- `Features/<Feature>/` — one folder per feature (`ScreenshotShelf`, `Annotation`, `VideoEditing`, `ScreenRecording`, `DropShelf`, `ImageSearch`, `Permissions`, `Settings`, `Toolbox`), plus `DynamicIsland`, each split into the relevant `Model/`, `ViewModel/`, `View/`, `Service/`, and `Presentation/` layers.
- `en.lproj/` + `tr.lproj/` — `Localizable.strings`.

## MVVM roles

- **`*ViewModel`** — `@MainActor ObservableObject` state + orchestration. They depend on **service protocols** (injected), and drive AppKit panels through `*Presenting` protocols via a `weak var presenter` — they do **not** construct `NSPanel`.
- **Services** — OS integrations behind protocols (`ScreenshotCapturing`, `ScreenRecordingServicing`, `ScreenRecordingSourceProviding`, `TextRecognizing`, `ScreenshotExporting`, `FinderPathProviding`, `DropShelfExporting`); concrete types are instances built in `AppEnvironment`. Permission services (`PrivacyPermissionService`, `ScreenRecordingPermissionService`) stay static OS gateways.
- **Presentation coordinators** (`*PanelCoordinator`) — own the `NSPanel` lifecycle, retained by `AppEnvironment`.

## Two settings systems — keep them in sync

Each feature threads a value through **all** of these; when you add or change a tool/setting, update every step or the UI silently drifts:

1. Model enum + `default*` constants + `Keys` (e.g. `ToolboxSettings` in `ToolboxTool.swift`).
2. `registerDefaults(defaults:)` — every key must appear in `defaultValues`.
3. `@AppStorage` use sites (menu in `DeskCastApp.swift`, `SettingsView`).
4. Menu-visibility logic — a tool shows only when `enabled && showInMenu` (see the `shouldShow*InMenu` computed vars). Disabled tools must never remain visible via `showInMenu`; `resetTools` enforces `enabled && showInMenu`.

There are six settings namespaces: `ToolboxSettings` (which tools/layout/language), `ScreenshotShelfSettings`, `ScreenRecordingSettings`, `DropShelfSettings`, `DynamicIslandSettings`, and `ColorPickerSettings`. Defaults are registered at launch in `AppEnvironment` and again inside the relevant view models.

## Localization

- All user-facing strings go through `AppLocalization.string(_:)` / `.formatted(_:_:)`, keyed by `Localizable.strings`. English is the fallback/base language.
- `AppLocalization` reads the chosen language from the `app.language` default and loads the matching `.lproj` bundle manually, so it works even though the app forces a locale via `.environment(\.locale, selectedLanguage.locale)` on every scene.
- Add new keys to **both** `en.lproj` and `tr.lproj/Localizable.strings`.

## Concurrency rules

- Stores are `@MainActor`. Background OCR/capture/indexing must hop back to main before touching `@Published` state, the pasteboard, panels, or views.
- Watch task cancellation and expiration/auto-hide timers: cancel timers when items are removed, pinned, cleared, or trimmed (see `expirationTimers` in `ScreenshotShelfViewModel`).
- Preserve pasteboard snapshot/restore in capture paths (`ScreenshotCaptureService`).

## Permissions

Entitlements grant Apple Events (`com.apple.security.automation.apple-events`) and user-selected read-write files only. Features depend on **Screen Recording** (capture/OCR/video), **Microphone** (optional recording audio), and **Automation → Finder** (copy path). Preserve the permission-denied → alert/toast flows (`PrivacyPermissionService`, `ScreenRecordingPermissionService`, `PermissionAlertPresenter`).

## Video recording architecture

- `ScreenRecordingViewModel` owns recorder state and persisted options; it never constructs windows.
- `ScreenRecordingPanelCoordinator` owns DeskCast's custom floating control panel and full-display selection overlay. The overlay returns a display-local, top-left-based source rect to ScreenCaptureKit.
- `ScreenCaptureRecordingService` owns `SCStream` + `SCRecordingOutput`; keep DeskCast excluded from its own capture and keep output `.mov`.
- `ScreenshotShelfViewModel` is the common media shelf. Video items use Quick Look thumbnails, open in the default player, and are copied/dragged as file URLs. Do not introduce a second video-only shelf.
- The macOS recording privacy indicator is system-owned and cannot be hidden; do not confuse it with DeskCast's custom recorder UI.

## Dynamic Island architecture

- Now Playing combines two sources in `MediaPlayerNowPlayingService`. (1) The system now playing session (browsers/YouTube, Podcasts, Music, Spotify, …) via `SystemNowPlayingBridge`: since macOS 15.4 MediaRemote only answers Apple platform binaries, so `NowPlayingAdapter/DeskCastNowPlaying.m` is built into `Contents/Frameworks/libDeskCastNowPlaying.dylib` by the target's "Build Now Playing Adapter" script phase and loaded into `/usr/bin/perl`, which streams JSON lines (`watch`), or sends a command/seek (`send`). (2) Music and Spotify over AppleScript (serial background queue, only for players already running), which adds the player's own volume and Spotify track ids; a scripted snapshot replaces the system one for the same app. There is no Spotify Web API connection (the "Up Next" queue was removed; macOS exposes no queue).
- Other apps' banners (Messages, Mail, browser Gmail, …) are mirrored by `SystemNotificationMonitorService`, which reads the `com.apple.notificationcenterui` process through the Accessibility API (AXObserver + 1 s poll, scans off-main, diffed against the previous scan). It needs the Accessibility permission and relies on Notification Center's private AX layout (`AXNotificationCenter…` subroles), so re-check it on new macOS releases. The island also shows DeskCast's own toasts (routed from `ToastPresenter.islandRouter`), track changes, and IOKit battery events (`BatteryMonitorService`).
- While a banner is showing, hover holds it (no expand); clicking opens the posting app.
- Expanded island = header + one `IslandPanel` page (Controls, Volume, Now Playing, Captures, Files, Clipboard, System, Tools, Calendar, Notifications, Timer, Camera, Downloads, Scratchpad, AI Agents) or the launcher grid, plus floating side buttons. `DynamicIslandView.layout(for:)` is the single source for island + side-button frames; per-page heights live in `expandedContentHeight(for:)`. Panel view models (`IslandPanelViewModels.swift`) poll only while their page is on screen (`activatesIslandPanel`). Open state: hover (transient), `isForcedOpen` (click/shortcut/side button; closes on outside click or pointer exit after entering), `isPinned` (pin button).
- Data sources: `SystemStatsService` (Mach host stats, IOAccelerator, `getifaddrs`, IOKit power), `AudioOutputService` (CoreAudio master/mic/devices), `AppVolumeService` (per-app volume via Core Audio process taps: an app below 100 % gets a `mutedWhenTapped` tap + private aggregate device + IO proc applying gain; apps at 100 % have no tap; needs System Audio Recording permission / `NSAudioCaptureUsageDescription`), `LyricsService` (LRCLIB, time-synced LRC), `AIUsageService` (Claude: OAuth usage endpoint with Claude Code's keychain token — never refreshed here — plus spend estimated from `~/.claude/projects` JSONL at API list prices; Codex: `rate_limits` events in `~/.codex/sessions`), EventKit calendar, AVFoundation camera, `~/Downloads`. Camera/calendar need the hardened-runtime entitlements and Info.plist usage strings already in the project.
- Clipboard history (`ClipboardHistoryViewModel` + `ClipboardHistoryService`) polls `NSPasteboard.changeCount` only while the island is on and the Clipboard panel isn't hidden, keeps ≤30 entries in memory, skips nspasteboard.org concealed/transient types, and forgets everything when recording stops — unless `dynamicIsland.savesClipboardHistory` (default off) is on: then `ClipboardHistoryFileStore` keeps ≤200 text/link/file entries (never images) in `~/Library/Application Support/DeskCast/ClipboardHistory.json` (0600), and turning it off (even while DeskCast isn't running) deletes the file. The panel has a search field (folds case, accents and Turkish ı); the island takes keyboard focus for it and hands focus back (`releaseKeyboardFocus`) before the synthetic ⌘V. Clicking an entry pastes it into the frontmost app via a synthetic ⌘V (Accessibility), since the island never takes focus.
- `EventReminderMonitor` posts an island banner 5 min before timed calendar events (setting `dynamicIsland.showsEventReminders`); it only reads EventKit when access was already granted by the Calendar panel.
- Panel shortcuts are ⌥⌘+letter `KeyboardShortcuts` names defined on `IslandPanel`, toggled by `DynamicIslandSettings.panelShortcutsEnabled`.
- `DynamicIslandPanelCoordinator` keeps a fixed-size transparent panel above the menu bar and toggles `ignoresMouseEvents` from global/local mouse-move monitors, so only the island shape takes clicks. Island sizes come from static metrics on `DynamicIslandView`; keep the coordinator's hover rect and the view in sync.

## Build & test

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -configuration Debug -destination 'platform=macOS' build
```

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -destination 'platform=macOS' test
```

Debug launch arguments for UI checks: `-DeskCastAllowsIslandCapture YES` (island visible to `screencapture`), `-DeskCastDemoPanel <panel|launcher>`, `-DeskCastDemoTrack YES`, `-DeskCastDemoTimer <min>`, `-DeskCastDemoNotification <text>`, `-DeskCastDemoMeeting <title>` (calendar reminder banner with a Join button), `-DeskCastDemoPin YES` (pins a sample screenshot on screen), `-DeskCastDemoAnnotate YES` (annotation editor on a sample image), `-DeskCastDemoVideo <path>` (Trim / GIF window on that video), `-DeskCastDemoSettings <section>`, `-DeskCastDemoMenuPanel YES` (menu panel in a plain window), and `-DeskCastSnapshotDir <folder>` (writes PNGs of all visible windows ~2.5 s after launch — works even while the screen is locked). `run-app.yml` uses these to upload screenshots as the `island-screenshots` artifact.

CI: `.github/workflows/build.yml` runs an unsigned Debug `build-for-testing`, the unit tests, and strict SwiftLint on every pushed branch (use it when no Mac is available). `release.yml` signs, notarizes and publishes — don't trigger it for checks.

Tests include placeholder Swift Testing units + XCTest UI tests that launch the accessory app. Before treating a UI-test failure as a regression, check whether it's just app launch/termination flakiness from the menu-bar/accessory activation.
