# Contributing to DeskCast

Thanks for your interest in improving DeskCast! This is a small SwiftUI + AppKit
macOS menu-bar app, and contributions of all sizes are welcome.

## Getting started

1. Fork and clone the repo.
2. Open `screenshotapp.xcodeproj` in Xcode, or build from the command line:
   ```bash
   xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -configuration Debug -destination 'platform=macOS' build
   ```
3. Run the tests before and after your change:
   ```bash
   xcodebuild -project screenshotapp.xcodeproj -scheme screenshotapp -destination 'platform=macOS' test
   ```
4. Lint before opening a PR — CI runs SwiftLint in strict mode, so warnings fail the build:
   ```bash
   brew install swiftlint   # once
   swiftlint lint --strict
   ```
   The ruleset lives in [.swiftlint.yml](.swiftlint.yml); `swiftlint --fix` auto-fixes the mechanical ones.

## Where things live

The code is organized by feature under `screenshotapp/Features/<Feature>/`, each
split into `Model`, `ViewModel`, `View`, `Service`, and `Presentation`. Shared
infrastructure lives in `Core/`, and the composition root is `App/AppEnvironment`.
See the Architecture section of the [README](README.md).

Please keep changes consistent with the existing structure:

- View models are `@MainActor` and depend on **service protocols**, not concrete
  types — inject new dependencies through `AppEnvironment`.
- Keep UI/state mutations on the main actor; hop background work back to main
  before touching `@Published` state, the pasteboard, panels, or views.
- User-facing strings go through `AppLocalization.string(_:)` and must be added to
  **both** `en.lproj` and `tr.lproj/Localizable.strings`.
- When adding or changing a setting/tool, update the whole chain: model
  defaults, `registerDefaults`, `@AppStorage` use sites, settings UI, and menu
  visibility.

## Pull requests

- Keep PRs focused and describe the change and how you tested it.
- Make sure the app builds and tests pass on macOS.
- For UI or behavior changes, a short screen recording or screenshots help.

## Publishing a release

DeskCast uses `MARKETING_VERSION` as its user-facing version. Update that value for
the app target in both Debug and Release configurations, then merge or push the
release commit to the `release` branch. The release workflow uses its run number as
the monotonically increasing `CFBundleVersion`.

The workflow archives, Developer ID signs, notarizes, and publishes these assets:

- `DeskCast.dmg` for first-time installation
- `DeskCast.zip` for in-app updates
- `appcast.xml`, signed by Sparkle and consumed by installed apps

The Sparkle private key must exist as the `SPARKLE_PRIVATE_KEY` GitHub Actions
secret. To configure it once, use Sparkle's `generate_keys` tool to export the key
from Keychain to a temporary file, upload it, then securely remove the file:

```bash
generate_keys -x /tmp/deskcast-sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/deskcast-sparkle-private-key
rm -f /tmp/deskcast-sparkle-private-key
```

Never commit the private key. The corresponding public key is intentionally stored
in the app target's generated Info.plist settings as `SUPublicEDKey`.

## Reporting issues

Open an issue with steps to reproduce, your macOS version, and what you expected
versus what happened.
