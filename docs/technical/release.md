# Release Process (Mac App Store)

Keypress is distributed through the Mac App Store. Pushing a `v*` tag triggers
GitHub Actions, which builds a sandboxed universal (arm64 + x86_64) app through
the Xcode project generated from `project.yml`, signs it for App Store
distribution, exports a `.pkg`, and uploads it to App Store Connect. Attaching
the build to a version and submitting for review is done manually in App Store
Connect.

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

The legacy certificate types (**Mac App Distribution** / identities named
"3rd Party Mac Developer Application/Installer") work too — the pipeline
detects identity names from the imported certificates automatically.

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

## Re-uploading a build under an already-tagged version

When the store version has to stay put — App Review rejected the build, or a fix
landed after the tag was cut — only `BUILD_NUMBER` moves. `bun run release`
refuses this case by design (its tag already exists), so the steps are manual:

1. Land the fix on `main`.
2. Fold the new entries into the existing `## [X.Y.Z] - <date>` section. Do
   **not** add an `## [Unreleased]` heading above it: CI runs
   `Scripts/validate_changelog.sh`, which fails when the top section is labeled
   Unreleased or does not match `MARKETING_VERSION`.
3. Bump `BUILD_NUMBER` in `version.env`, leave `MARKETING_VERSION` alone.
4. Push `main`, then tag and push:

```bash
git tag v1.1.0-build.9 && git push origin v1.1.0-build.9
```

The workflow accepts both `v<version>` and `v<version>-build.<n>`. Build numbers
never reset when the marketing version changes — they grow across the whole
project, so a re-upload and a new version both just take the next one.

Never move an existing tag with `git tag -f`: it burns App Store build numbers
and makes the history untraceable. `workflow_dispatch` on release.yml does the
same job without any tag, reusing whatever `version.env` holds on `main`.

## What CI does (`.github/workflows/release.yml`)

1. Verifies the tag matches `MARKETING_VERSION` and sits on `origin/main`;
   validates the changelog; runs tests.
2. Imports both distribution certificates into a temporary keychain.
3. `Scripts/build_appstore.sh` — generates the Xcode project from `project.yml`
   (xcodegen), then `xcodebuild archive` + `-exportArchive` (method
   `app-store-connect`) produce the signed universal `.pkg`. Building through
   Xcode is load-bearing: App Store server-side processing **silently drops**
   hand-assembled bundles (no error, no email — the build just never appears),
   because they lack metadata Xcode stamps automatically
   (`application-identifier` entitlements, `DTXcode`/`DTSDK*` keys,
   `CFBundleSupportedPlatforms`, …). Do not replace this with a manual
   `swift build` + `codesign` + `productbuild` pipeline.
4. `Scripts/upload_appstore.sh` — validates and uploads via `altool` with the
   App Store Connect API key.

Dev builds (`bun run start` → `Scripts/package_app.sh`) go through the same
Xcode project, so the local app and the store artifact cannot drift apart.

## Sandbox notes

- The app runs sandboxed (required for the App Store). Key monitoring uses a
  listen-only CGEvent tap, which works in the sandbox once the user grants
  **Input Monitoring** (System Settings → Privacy & Security), requested via
  `IOHIDRequestAccess`.
- No Accessibility API is used anywhere: App Review rejects that under
  guideline 2.4.5. Auto monitor selection uses the pointer's screen instead.
- A locally built (`bun run start`) copy is unsandboxed and uses the same
  Input Monitoring permission path.

## Troubleshooting

- **`altool` validation errors** — the output lists concrete issues (missing
  icon, bundle ID mismatch with the profile, non-incremented build number).
- **Workflow failed after the tag was pushed** — fix on `main`, bump
  `BUILD_NUMBER`, and push a build-suffixed tag (see
  [Re-uploading a build](#re-uploading-a-build-under-an-already-tagged-version)).
- **Upload succeeded but the build never appears** — check the email from App
  Store Connect: processing rejections (e.g. entitlement/profile mismatch)
  arrive as mail to the account holder.
- **No identity found** — the `.p12` was exported without the private key, or
  the wrong certificate type was created.
