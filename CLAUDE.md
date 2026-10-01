# CLAUDE.md

Guidance for Claude Code when working in this repo. See [AGENTS.md](AGENTS.md) for the detailed editing rules and review checklist — this file complements it with the concrete architecture map. When they conflict, AGENTS.md wins.

## What this is

A macOS menu-bar utility toolbox. It bundles several small productivity tools behind a single `MenuBarExtra`:

- **Capture Selected Area** — `screencapture`-based region capture into a floating media shelf. Image captures can be annotated (`Features/Annotation`: arrow, rectangle, pen, text, highlight, pixelate; Done replaces the shelf image and rewrites its saved PNG) or pinned on screen as always-on-top panels.
- **Capture Video** — full-display or resizable selected-area recording through ScreenCaptureKit and DeskCast's own recorder panel, with system-audio/microphone options. Completed videos join screenshots in the same shelf, where "Trim or Make GIF…" (`Features/VideoEditing`) saves a passthrough-trimmed copy (added to the shelf) or a looping GIF next to the original, which is never overwritten.
- **Scrolling Capture** — select an area, scroll it yourself; `ScrollingFrameCaptureService` grabs the area through `SCScreenshotManager` (DeskCast excluded) every ~120 ms and `ScrollStitcher` (pure, unit-tested) finds the vertical offset from grayscale row signatures, ignores fixed header/footer bands (footer appended once), and keeps only newly revealed strips (≤20 000 px). The result joins the screenshot shelf.
- **Capture OCR** — capture a region and copy recognized text, or the contents of QR codes/barcodes in it (Vision).
- **Pick Color** — system loupe (`NSColorSampler`, no Screen Recording permission) copies the picked color as HEX/RGB/HSL/SwiftUI; the last 8 colors show in the menu panel.
- **Copy Finder Path** — copy the front Finder window's path via AppleScript.
- **Search Images** — index and search local images by filename + recognized text.
- **Drop Shelf** — a floating shelf that collects dragged files/folders/links/text/images to send together.
- **AI agents hub** (`Features/AgentHub`, the island's AI Agents panel — Sessions / Ask / Usage / Connections; Coucou-inspired) — follows Claude Code sessions through hooks and answers permission requests from the island, chats with Claude about files or windows, and shows Stripe/Vercel/n8n/GitHub/Resend/Notion/Cal.com, with Bip, DeskCast's own code-drawn mascot.
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
- `Features/<Feature>/` — one folder per feature (`ScreenshotShelf`, `Annotation`, `VideoEditing`, `ScrollingCapture`, `ScreenRecording`, `DropShelf`, `ImageSearch`, `Permissions`, `Settings`, `Toolbox`), plus `DynamicIsland`, each split into the relevant `Model/`, `ViewModel/`, `View/`, `Service/`, and `Presentation/` layers.
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

- Now Playing combines two sources in `MediaPlayerNowPlayingService`. (1) The system now playing session (browsers/YouTube, Podcasts, Music, Spotify, …) via `SystemNowPlayingBridge`: since macOS 15.4 MediaRemote only answers Apple platform binaries, so `NowPlayingAdapter/DeskCastNowPlaying.m` is built into `Contents/Frameworks/libDeskCastNowPlaying.dylib` by the target's "Build Now Playing Adapter" script phase and loaded into `/usr/bin/perl`, which streams JSON lines (`watch`), or sends a command/seek (`send`). Play/pause sends explicit play or pause (not toggle) and holds the optimistic state ~2 s against stale readings; the adapter's `send` spins the run loop 0.3 s before exiting so MediaRemote delivers the command. (2) Music and Spotify over AppleScript (serial background queue, only for players already running), which adds the player's own volume and Spotify track ids; a scripted snapshot replaces the system one for the same app. There is no Spotify Web API connection (the "Up Next" queue was removed; macOS exposes no queue).
- Closed-island activities (`IslandActivity`: music, working AI agent, timer — automatic order in that order; a running timer rides on the right wing beside music or an agent). With ≥2 going on, chips under the island (hovered closed island or open island; frames in `DynamicIslandLayout.chipFrames`) pick one (`activityChoice`, cleared when that activity ends) or Automatic. Opening goes to the shown activity's page (`opensToActivity`, `activityPanel`); otherwise `reopenTarget` (last panel, launcher, or a fixed `.panel`), and `contentBeforeActivity` keeps activity jumps from replacing the last panel.
- AI agent activity: `AgentActivityService` watches `~/.claude/projects` and `~/.codex/sessions` with FSEvents (plus a 2 s poll of Codex transcripts: Codex keeps its file open and FSEvents reports writes only on close) and reads each transcript from its last offset (tail 512 KB on start, and silently the same way for a transcript first seen or swept after 30 min idle — replaying it announced every past turn; turns that ended >60 s ago are never announced); `AgentTranscriptState` (pure, unit-tested) tracks a turn — Claude Code: prompt → assistant `end_turn` (sidechains, `subagents/`, slash commands, interruptions handled), Codex: `task_started` → `task_complete`/`turn_aborted` (sub-threads skipped). Turns idle 30 min are dropped. `AgentActivityMonitor` shows them (`.compactAgent`) and announces turns ≥ `agentFinishMinimumMinutes` as a "finished" alert.
- Other apps' banners (Messages, Mail, browser Gmail, …) are mirrored by `SystemNotificationMonitorService`, which reads the `com.apple.notificationcenterui` process through the Accessibility API (AXObserver + 1 s poll, scans off-main, diffed against the previous scan). It needs the Accessibility permission and relies on Notification Center's private AX layout (`AXNotificationCenter…` subroles), so re-check it on new macOS releases. The island also shows DeskCast's own toasts (routed from `ToastPresenter.islandRouter`; success toasts stay in the closed island's wings as `.compactToast` for ~2 s and don't hold on hover, warnings/errors get a banner; DeskCast alerts — timer, battery, finished agent, meetings without a Join link — go through `postAlert`/`postReminder` and peek in the wings via `asPeek` unless `dynamicIsland.fullBanners` is on), an optional new-song peek in the wings (off by default, like Vorssaint — playback otherwise goes straight to compact music), and IOKit battery events (`BatteryMonitorService`).
- While a banner is showing, hover holds it (no expand); clicking opens the posting app.
- Expanded island = header + one `IslandPanel` page (Controls, Volume, Now Playing, Captures, Files, Clipboard, System, Tools, Calendar, Notifications, Timer, Camera, Downloads, Scratchpad, AI Agents, Devices, Weather) or the launcher grid (drag tiles to reorder; Edit hides/adds panels, writing the same `panelOrder`/`hiddenPanels` defaults as Settings), plus floating side buttons. `DynamicIslandView.layout(for:)` is the single source for island + side-button frames; per-page heights live in `expandedContentHeight(for:)`. Panel view models (`IslandPanelViewModels.swift`) poll only while their page is on screen (`activatesIslandPanel`). Open state: hover (transient), `isForcedOpen` (click/shortcut/side button, and any page switch — a resize can leave the pointer outside; closes on outside click or pointer exit after entering), `isPinned` (pin button).
- Data sources: `SystemStatsService` (Mach host stats, IOAccelerator, `getifaddrs`, IOKit power), `AudioOutputService` (CoreAudio master/mic/devices), `AppVolumeService` (per-app volume via Core Audio process taps: an app below 100 % gets a `mutedWhenTapped` tap + private aggregate device + IO proc applying gain; apps at 100 % have no tap; needs System Audio Recording permission / `NSAudioCaptureUsageDescription`), `LyricsService` (LRCLIB, time-synced LRC), `AIUsageService` (Claude: OAuth usage endpoint with Claude Code's keychain token — never refreshed here — plus spend estimated from `~/.claude/projects` JSONL at API list prices; Codex: `rate_limits` events in `~/.codex/sessions`), EventKit calendar, AVFoundation camera, `~/Downloads`. Camera/calendar need the hardened-runtime entitlements and Info.plist usage strings already in the project.
- Devices panel (`DevicesViewModel`): connected Bluetooth accessories' battery. `SystemProfilerBluetoothService` runs `system_profiler SPBluetoothDataType -json` (no permission; AirPods left/right/case, Apple and many other devices; only `device_connected`, since macOS keeps stale levels for disconnected AirPods; values may be localized like "%52"). `BLEBatteryService` reads the standard Battery Service (0x180F/0x2A19) of connected LE peripherals via CoreBluetooth (e.g. Logitech MX) — needs Bluetooth permission (`NSBluetoothAlwaysUsageDescription`), requested only from the panel's button. Polls every 30 s while the panel is on screen.
- Clipboard history (`ClipboardHistoryViewModel` + `ClipboardHistoryService`) polls `NSPasteboard.changeCount` only while the island is on and the Clipboard panel isn't hidden, keeps ≤30 entries in memory, skips nspasteboard.org concealed/transient types, and forgets everything when recording stops — unless `dynamicIsland.savesClipboardHistory` (default off) is on: then `ClipboardHistoryFileStore` keeps ≤200 text/link/file entries (never images) in `~/Library/Application Support/DeskCast/ClipboardHistory.json` (0600), and turning it off (even while DeskCast isn't running) deletes the file. The panel has a search field (folds case, accents and Turkish ı); the island takes keyboard focus for it and hands focus back (`releaseKeyboardFocus`) before the synthetic ⌘V. Clicking an entry pastes it into the frontmost app via a synthetic ⌘V (Accessibility), since the island never takes focus.
- Weather (`WeatherViewModel` + `OpenMeteoWeatherService`): Open-Meteo, no key and no location permission — the city typed in Settings (`dynamicIsland.weatherCity`) is geocoded, then forecast with `timeformat=unixtime`; `OpenMeteoParser` is pure and unit-tested. Idle content `.weather` shows it in the closed island (`.compactWeather`, music still wins while playing); it refreshes every 30 min only while shown there or while the panel is open.
- Idle content (`IslandIdleContent`, default `.automatic`; a stored `.music` — the old default — is migrated once): `DynamicIslandViewModel.idleMode` (`DynamicIslandViewModel+IdleContent.swift`) picks `.compactEvent` / `.compactClaude` / `.compactBattery` / `.compactWeather`. Automatic: music while playing, then a meeting within the hour, Claude's 5-hour limit ≥ 70 %, battery ≤ 20 %, weather, a later event, the Claude limit. `IdleInfoMonitor` refreshes `idleEvent` (EventKit, only once Calendar access exists) and `idleClaudeUsage` (`AIUsageService.claudeSessionUsage`, one small file) once a minute while the choice needs them.
- Focus indicator (`FocusIndicatorMonitor` + `SystemFocusStatusService`): `INFocusStatusCenter` only says on/off, needs the Communication Notifications entitlement (`com.apple.developer.usernotifications.communication`, so a Developer ID provisioning profile — release's `-allowProvisioningUpdates` makes it) plus `NSFocusStatusUsageDescription`; access is asked when the setting (`dynamicIsland.showsFocusIndicator`, default off) is turned on. Polled every 2 s while on; `.compactFocus` is the lowest-priority closed mode, and battery/weather get a small moon.
- Notification history (≤50) is saved to `~/Library/Application Support/DeskCast/NotificationHistory.json` (0600; Clear erases it). Banners suppressed by a Focus never show, so when the full Notification Center is open (more than 2 new items in one scan) its visible list is imported into the history silently (`onNotificationCenterList`); NC's list isn't readable while it's closed.
- AI spend: `ClaudeTranscriptScanner` pulls only the `usage` object out of transcript lines, and `TranscriptSpendSummary` extends per-file totals from the last parsed byte; the summaries are cached in `~/Library/Caches/DeskCast/ClaudeSpendCache.json`, so only a first-ever scan reads every transcript. Limits load and publish before spend, and a warm-up runs ~8 s after launch.
- `EventReminderMonitor` posts an island banner 5 min before timed calendar events (setting `dynamicIsland.showsEventReminders`); it only reads EventKit when access was already granted by the Calendar panel.
- Panel shortcuts are ⌥⌘+letter `KeyboardShortcuts` names defined on `IslandPanel`, toggled by `DynamicIslandSettings.panelShortcutsEnabled`.
- `DynamicIslandPanelCoordinator` keeps a fixed-size transparent panel above the menu bar and toggles `ignoresMouseEvents` from global/local mouse-move monitors, so only the island shape takes clicks. Island sizes come from static metrics on `DynamicIslandView`; keep the coordinator's hover rect and the view in sync.

## AI agents hub

- Claude Code hooks: `ClaudeHookConfiguration` (pure, unit-tested) merges/removes DeskCast's entries (command contains `deskcast-hook`) in `~/.claude/settings.json`; `ClaudeHookInstallService` only writes after the user approved the shown diff, makes a dated backup first and refuses if the file changed since the preview. Other tools' hooks stay.
- The hook command is a Perl relay (`AgentHookRelay`, written to `~/Library/Application Support/DeskCast/bin/deskcast-hook`; Perl because python3 needs the developer tools). It adds terminal context (TERM_PROGRAM, tty, iTerm session) and sends the JSON to `AgentHookServer` (Unix socket `…/DeskCast/agent-hook.sock`, 0600, same-uid check). It always exits 0 and gives up after 0.3 s, so Claude Code is never blocked. Only `PermissionRequest` waits: DeskCast replies with the hook's decision JSON, or an empty line (→ Claude Code asks in the terminal) on timeout (`agentHub.approvalTimeout`), "Answer in terminal", or when any later event of that session shows it was answered there.
- `AgentHubState` (pure, unit-tested) turns hook events into sessions (phase, last steps, last message, question). `AskUserQuestion` can't be answered by a hook, so questions get a "Answer in terminal" button (`TerminalJumpService`: Terminal tab by tty / iTerm session via osascript, VS Code/Cursor folder, else activate the app).
- `AgentHubViewModel` (built in `IslandPanelModels`, also handed to Settings) pins the island open on the AI Agents panel while a request waits (`beginAttention`/`endAttention` on `DynamicIslandViewModel`). Settings: `AgentHubSettings` (`agentHub.*`), pane `AgentHubSettingsPane`.
- Ask page (`AgentChatViewModel`, `ClaudeChatProtocol` pure + unit-tested, `ClaudeMessagesService`): the user's own Anthropic key in the Keychain (`AgentKeychain`, this-device-only), raw HTTPS to the Messages API (no Swift SDK) with web search (`web_search_20260209` on current models) and `fallbacks: "default"` for refusals; the content of each reply (thinking/search blocks) goes back unchanged, `pause_turn` is continued. Default model `claude-opus-5-5`, list from `GET /v1/models`. Files dropped on the page are attached (PDF/image blocks, text ≤200 KB) or mailed with Apple Mail (`MailSendService`, osascript with argv, Send button only). Dragging Bip onto a window (`BipDragPresenter` ghost + rainbow halo) attaches that window (`WindowContextService`: window list → ScreenCaptureKit picture, browser URL). The island takes keyboard focus on the Ask page like the scratchpad.
- Connections page (`AgentIntegrationsViewModel`, `IntegrationClient`, `IntegrationParsers` pure + unit-tested): Stripe, Vercel, n8n (https base URL in `agentHub.n8nURL`, retry via the public API), GitHub, Resend, Notion, Cal.com — each only polled while turned on (`agentHub.activeIntegrations`) and with a Keychain key. The first reading is silent; later new Stripe payments, finished Vercel deployments and failed n8n runs are announced with `postAlert`. Each service has its own tinted Bip (`BipMascotView(tint:)`).
- Bip (`BipMascotView`, `BipMood`) is drawn in a `Canvas`; its sounds are synthesized by `BipSoundPlayer` (no sound files). Coucou's name, Mochi character, icons and sounds are not MIT-licensed — never copy them.

## Build & test

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -configuration Debug -destination 'platform=macOS' build
```

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -destination 'platform=macOS' test
```

Debug launch arguments for UI checks: `-DeskCastAllowsIslandCapture YES` (island visible to `screencapture`), `-DeskCastDemoPanel <panel|launcher>`, `-DeskCastDemoTrack YES`, `-DeskCastDemoTimer <min>`, `-DeskCastDemoNotification <text>`, `-DeskCastDemoToast <text>` (compact DeskCast confirmation, ~2 s), `-DeskCastDemoFocus YES` (Focus indicator on), `-DeskCastDemoMeeting <title>` (calendar reminder banner with a Join button), `-DeskCastDemoPin YES` (pins a sample screenshot on screen), `-DeskCastDemoAnnotate YES` (annotation editor on a sample image), `-DeskCastDemoVideo <path>` (Trim / GIF window on that video), `-DeskCastDemoScrollFrame <png>` (one scrolling-capture frame of main-display area 100,100 600×400 pt), `-DeskCastDemoSettings <section>`, `-DeskCastDemoMenuPanel YES` (menu panel in a plain window), and `-DeskCastSnapshotDir <folder>` (writes PNGs of all visible windows ~2.5 s after launch — works even while the screen is locked). `run-app.yml` uses these to upload screenshots as the `island-screenshots` artifact.

CI: `.github/workflows/build.yml` runs an unsigned Debug `build-for-testing`, the unit tests, and strict SwiftLint on every pushed branch (use it when no Mac is available). `release.yml` signs, notarizes and publishes — don't trigger it for checks.

Tests include placeholder Swift Testing units + XCTest UI tests that launch the accessory app. Before treating a UI-test failure as a regression, check whether it's just app launch/termination flakiness from the menu-bar/accessory activation.
