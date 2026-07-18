# Release Process (Mac App Store)

Keypress is distributed through the Mac App Store. Pushing a `v*` tag triggers
GitHub Actions, which builds a sandboxed universal (arm64 + x86_64) binary,
signs it for App Store distribution, packages it as a `.pkg`, and uploads it to
App Store Connect. Attaching the build to a version and submitting for review
is done manually in App Store Connect.

## One-time setup (Apple Developer account holder)

Requires a paid Apple Developer Program membership. Certificates and API keys
below can only be created by the **Account Holder** (or Admin, where noted).

### 1. Certificates

Two certificates are needed, both created at
[Certificates](https://developer.apple.com/account/resources/certificates/add)
from a CSR (Keychain Access → Certificate Assistant → Request a Certificate
From a Certificate Authority → Saved to disk):

1. **Apple Distribution** — signs the app bundle.
2. **Mac Installer Distribution** — signs the installer `.pkg`.

Download both `.cer` files, double-click to add them to the Keychain of the Mac
that created the CSR, then export each from Keychain Access → My Certificates
as a password-protected `.p12` (the entry must expand to show the private key).

### 2. App ID and provisioning profile

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
   → register an **App ID** with bundle ID `dev.keypress.app` (explicit).
2. [Profiles](https://developer.apple.com/account/resources/profiles/add) →
   **Mac App Store Connect** distribution profile → select the App ID, Mac
   profile type, and the Apple Distribution certificate → download the
   `.provisionprofile`.

### 3. App record in App Store Connect

[App Store Connect → Apps](https://appstoreconnect.apple.com/apps) → **+** →
New App → platform macOS, bundle ID `dev.keypress.app`, any SKU (e.g.
`keypress`). Metadata (screenshots, description, privacy) can be filled in
later, but the record must exist before the first upload.

In App Privacy / Review Notes, explain that the app uses the Input Monitoring
permission to visualize typed keys on screen and that no keystroke data is
stored or transmitted.

### 4. App Store Connect API key (for CI uploads)

[Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api)
→ generate a key with the **App Manager** role. Download the `.p8` (one-time
download), note the **Key ID** and **Issuer ID**.

### 5. GitHub secrets

Repo → Settings → Secrets and variables → Actions, or via `gh`:

```bash
base64 -i AppleDistribution.p12 | gh secret set APPLE_DISTRIBUTION_CERT_P12_BASE64
gh secret set APPLE_DISTRIBUTION_CERT_PASSWORD
base64 -i MacInstaller.p12 | gh secret set MAC_INSTALLER_CERT_P12_BASE64
gh secret set MAC_INSTALLER_CERT_PASSWORD
base64 -i Keypress.provisionprofile | gh secret set PROVISIONING_PROFILE_BASE64
gh secret set APP_STORE_CONNECT_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8
gh secret set APP_STORE_CONNECT_KEY_ID
gh secret set APP_STORE_CONNECT_ISSUER_ID
```

| Secret | Contents |
|--------|----------|
| `APPLE_DISTRIBUTION_CERT_P12_BASE64` | Apple Distribution `.p12`, base64 |
| `APPLE_DISTRIBUTION_CERT_PASSWORD` | Its export password |
| `MAC_INSTALLER_CERT_P12_BASE64` | Mac Installer Distribution `.p12`, base64 |
| `MAC_INSTALLER_CERT_PASSWORD` | Its export password |
| `PROVISIONING_PROFILE_BASE64` | Mac App Store `.provisionprofile`, base64 |
| `APP_STORE_CONNECT_API_KEY_P8` | Full text of the `.p8` API key |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID |

Signing identity names are derived automatically from the certificates.

## Cutting a release

1. Make sure `CHANGELOG.md` has an `## [Unreleased]` section describing the
   release.
2. From a clean `main` in sync with origin:

```bash
bun run release 0.2.0
```

The script runs lint/tests, renames `## [Unreleased]` to `## [0.2.0] - <today>`,
bumps `MARKETING_VERSION`/`BUILD_NUMBER` (App Store Connect requires the build
number to grow), asks for confirmation, then commits, tags `v0.2.0`, pushes,
and watches the workflow.

When the workflow finishes, the build appears in App Store Connect (processing
takes a few minutes). There: select the build for the version, fill in "What's
New" from the changelog, and submit for review.

## What CI does (`.github/workflows/release.yml`)

1. Verifies the tag matches `MARKETING_VERSION` and sits on `origin/main`;
   validates the changelog; runs tests.
2. Imports both distribution certificates into a temporary keychain.
3. `Scripts/build_appstore.sh` — universal build, embeds the provisioning
   profile, signs with the App Sandbox entitlements (`Keypress.entitlements`),
   builds the signed `.pkg`.
4. `Scripts/upload_appstore.sh` — validates and uploads via `altool` with the
   App Store Connect API key.

## Sandbox notes

- The app runs sandboxed (required for the App Store). Key monitoring uses a
  listen-only CGEvent tap, which works in the sandbox once the user grants
  **Input Monitoring** (System Settings → Privacy & Security), requested via
  `IOHIDRequestAccess`.
- Accessibility APIs are unavailable in the sandbox: the "follow the frontmost
  window" monitor selection degrades gracefully to the main screen.
- A locally built (`bun run start`) copy is unsandboxed and uses the same
  Input Monitoring permission path.

## Troubleshooting

- **`altool` validation errors** — the output lists concrete issues (missing
  icon, bundle ID mismatch with the profile, non-incremented build number).
- **Workflow failed after the tag was pushed** — fix on `main`, then re-tag:
  `git tag -f v0.2.0 && git push -f origin v0.2.0`.
- **Upload succeeded but the build never appears** — check the email from App
  Store Connect: processing rejections (e.g. entitlement/profile mismatch)
  arrive as mail to the account holder.
- **No identity found** — the `.p12` was exported without the private key, or
  the wrong certificate type was created.
