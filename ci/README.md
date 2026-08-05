# App Store release automation

Pushing (or merging) to the **`release`** branch runs
`.github/workflows/appstore-release.yml`, which archives the Mac App Store build,
exports a signed `.pkg`, and uploads it to App Store Connect. It can also be run
manually from the **Actions** tab (`workflow_dispatch`).

## One-time prerequisites

1. **App Store Connect app record** for bundle id `com.ahmetbugraozcan.screenshotapp`
   (team `2T78BG3872`). The upload target must already exist.
2. **Distribution certificates** exported as a single `.p12`:
   - *Apple Distribution* (app signing) and
   - *Mac Installer Distribution* (`.pkg` signing).
   Export both into one `.p12` from Keychain Access, note the password.
3. **App Store Connect API key** (Users and Access → Integrations → App Store Connect
   API): download the `.p8`, and note the **Key ID** and **Issuer ID**. Give it the
   *App Manager* role.

## Required GitHub repository secrets

Settings → Secrets and variables → Actions → *New repository secret*:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | `base64 -i certs.p12` output |
| `P12_PASSWORD` | password used when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any random string (temp CI keychain) |
| `APP_STORE_CONNECT_API_KEY_ID` | the API Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | the API Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` output |

Generate the base64 values locally, e.g.:

```bash
base64 -i certs.p12 | pbcopy
base64 -i AuthKey_ABC123.p8 | pbcopy
```

## Notes / caveats

- The runner needs an Xcode whose SDK matches this project's deployment target
  (`MACOSX_DEPLOYMENT_TARGET = 26.0`). If `macos-latest` doesn't yet ship that SDK,
  either pin a newer image / `xcode-select` a specific Xcode, or lower the deployment
  target. A self-hosted runner is the fallback.
- Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (or let
  `manageAppVersionAndBuildNumber` handle the build number) before each release, or
  App Store Connect will reject a duplicate build.
- `altool` is used for the upload; if it is ever removed, switch the last step to
  `xcrun iTMSTransporter` or the Transporter app.
