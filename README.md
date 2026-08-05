# DeskCast

A lightweight macOS **menu-bar toolbox** for everyday desktop work. DeskCast lives
in the menu bar (no Dock icon) and bundles a few focused tools:

- **Screenshot shelf** — capture a screen region into a floating shelf; reorder,
  pin, copy, drag out to other apps, save (or auto-save), and reveal in Finder.
- **Drop shelf** — a floating tray that collects dragged files, folders, links,
  text, and images so you can gather them up and send them somewhere together.
  Opens on a shake while you're dragging content.
- **Image text search** — index a folder and search local images by filename and
  recognized text (Vision OCR).
- **Copy Finder path** — copy the front Finder window's path to the clipboard.

Every tool can be toggled and shown/hidden in the menu, and the whole UI is
localized (English + Turkish).

## Requirements

- macOS (Apple Silicon or Intel). The project's deployment target is set in
  `screenshotapp.xcodeproj`.
- Xcode with a matching macOS SDK.

## Build & run

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -configuration Debug -destination 'platform=macOS' build
```

Or open `screenshotapp.xcodeproj` in Xcode and run the `screenshotapp` scheme.

Run the unit tests with:

```bash
xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -destination 'platform=macOS' test
```

## Permissions

DeskCast asks for standard macOS permissions only when a feature needs them:
Screen Recording (capture/OCR), Automation → Finder (copy path), and
Accessibility (shake-to-open). It is distributed outside the Mac App Store
(Developer ID / notarized), so it is not sandboxed.

## Architecture

DeskCast is a SwiftUI + AppKit app organized as a layered, feature-module MVVM
codebase:

```
screenshotapp/
  App/       @main app, AppDelegate, AppEnvironment (composition root / DI)
  Core/      cross-cutting: localization, shared UI, support helpers, ShelfCollecting
  Features/  ScreenshotShelf · DropShelf · ImageSearch · Permissions · Settings · Toolbox
             each split into Model / ViewModel / View / Service / Presentation
```

- **View models** (`*ViewModel`) are `@MainActor ObservableObject`s that hold state
  and orchestrate services. They depend on **protocols**, not concrete services.
- **Services** wrap OS integrations (screen capture, Vision OCR, export, Finder)
  behind protocols (`ScreenshotCapturing`, `TextRecognizing`, …) so they can be
  faked in tests.
- **`AppEnvironment`** is the composition root: it builds the view models, injects
  their dependencies, and owns the presentation coordinators — no singletons.
- **Presentation coordinators** own the AppKit `NSPanel` lifecycle; view models
  drive them through `*Presenting` protocols instead of touching AppKit directly.

See [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md) for deeper notes.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Ahmet Buğra Özcan
