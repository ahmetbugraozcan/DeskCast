# Release automation (Developer ID + notarization)

Pushing (or merging) to the **`release`** branch runs
`.github/workflows/release.yml`, which builds DeskCast with a **Developer ID**
certificate, notarizes and staples the app, packages a signed & notarized
`.dmg`, and publishes it to **GitHub Releases**. Link that `.dmg` from your own
site for distribution. The workflow can also be run from the **Actions** tab
(`workflow_dispatch`).

This path does **not** use the App Store or App Sandbox — the app ships as a
notarized Developer ID build, so every current feature works as-is.

## One-time prerequisites

1. **Apple Developer Program** membership (team `2T78BG3872`).
2. **Developer ID Application** certificate, exported as a single `.p12` from
   Keychain Access (note the export password). This is the only certificate
   needed — no Mac App Store certificates.
3. **App Store Connect API key** (Users and Access → Integrations → App Store
   Connect API), used by `notarytool` for notarization: download the `.p8`, and
   note the **Key ID** and **Issuer ID**.

## Required GitHub repository secrets

Settings → Secrets and variables → Actions → *New repository secret*:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i developer_id.p12` output |
| `P12_PASSWORD` | password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string (temp CI keychain) |
| `APP_STORE_CONNECT_API_KEY_ID` | the API Key ID (for notarization) |
| `APP_STORE_CONNECT_API_ISSUER_ID` | the API Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` output |

Generate the base64 values locally, e.g.:

```bash
base64 -i developer_id.p12 | pbcopy
base64 -i AuthKey_ABC123.p8 | pbcopy
```

## Notes / caveats

- The runner needs an Xcode whose SDK matches this project's deployment target
  (`MACOSX_DEPLOYMENT_TARGET = 26.0`). If `macos-latest` doesn't yet ship that
  SDK, pin a newer image / `xcode-select` a specific Xcode, or use a self-hosted
  runner.
- Hardened Runtime is already enabled (required for notarization).
- The release tag is `v<version>-<run-number>` and marked as a prerelease; bump
  `MARKETING_VERSION` in the project for a clean versioned release.
- Both the `.app` and the `.dmg` are notarized and stapled, so Gatekeeper opens
  the download cleanly offline.
- The GitHub Release step uses `softprops/action-gh-release`; the workflow grants
  it `contents: write`.
