# Release Process

Releases are fully automated through GitHub Actions. Pushing a `v*` tag builds a
universal (arm64 + x86_64) binary, signs it with a Developer ID certificate,
notarizes it with Apple, publishes a GitHub release, and updates the Sparkle
update feed (`appcast.xml`).

## One-time setup

### 1. Credentials from the Apple Developer account holder

Ask the certificate owner for:

1. **Developer ID Application certificate** exported as `.p12`:
   - Keychain Access → My Certificates → right-click the
     `Developer ID Application: … (TEAMID)` certificate → Export → `.p12` with a
     password. The export must include the **private key** (the certificate must
     be expandable in Keychain Access and show a key underneath).
2. **App Store Connect API key** (used for notarization):
   - [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
   - Create a **Team key** with the **Developer** role.
   - They should send: the `.p8` file, the **Key ID**, and the **Issuer ID**
     (shown at the top of that page).

Both items are secrets — transfer them over a secure channel, not email/chat.

### 2. Sparkle EdDSA key

The appcast is signed with an ed25519 key. The matching public key is baked into
the app (`SUPublicEDKey` in `Scripts/package_app.sh`).

If the key was generated on this machine, it is in the login Keychain. Export it
with Sparkle's tools (from `.build/artifacts/` or a
[Sparkle release](https://github.com/sparkle-project/Sparkle/releases)):

```bash
./bin/generate_keys -x sparkle_private_key
```

Then confirm the pair matches the app: `./bin/generate_keys -p` prints the
public key — it must equal `SUPublicEDKey` in `Scripts/package_app.sh`. A
mismatch is not caught by CI: releases would publish fine, but installed apps
would silently reject every update.

If the private key is lost, run `./bin/generate_keys` to create a new pair and
update `SUPublicEDKey` in `Scripts/package_app.sh` to the printed public key
(safe before the first public release; after that, existing installs would stop
accepting updates).

### 3. GitHub secrets

Add the secrets (repo → Settings → Secrets and variables → Actions, or `gh`):

```bash
base64 -i DeveloperID.p12 | gh secret set APPLE_CERTIFICATE_P12_BASE64
gh secret set APPLE_CERTIFICATE_PASSWORD          # p12 export password
gh secret set APP_STORE_CONNECT_API_KEY_P8 < AuthKey_XXXXXXXXXX.p8
gh secret set APP_STORE_CONNECT_KEY_ID            # e.g. XXXXXXXXXX
gh secret set APP_STORE_CONNECT_ISSUER_ID         # UUID from the API page
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key
```

| Secret | Contents |
|--------|----------|
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application `.p12`, base64-encoded |
| `APPLE_CERTIFICATE_PASSWORD` | Password of the `.p12` export |
| `APP_STORE_CONNECT_API_KEY_P8` | Full text of the `.p8` API key |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID |
| `SPARKLE_PRIVATE_KEY` | Exported ed25519 private key file contents |

The signing identity name is derived automatically from the certificate — no
secret needed for it.

## Cutting a release

1. Make sure `CHANGELOG.md` has an `## [Unreleased]` section describing the
   release.
2. From a clean `main` in sync with origin:

```bash
bun run release 0.2.0
```

The script:

- runs SwiftFormat/SwiftLint/tests locally,
- renames `## [Unreleased]` to `## [0.2.0] - <today>`,
- sets `MARKETING_VERSION` and increments `BUILD_NUMBER` in `version.env`
  (Sparkle compares `CFBundleVersion`, so the build number must grow every
  release),
- shows the diff and asks for confirmation,
- commits `chore: release 0.2.0`, tags `v0.2.0`, pushes, and watches the
  workflow.

After the release, start the next `CHANGELOG.md` entry by adding a fresh
`## [Unreleased]` section on top.

## What CI does (`.github/workflows/release.yml`)

1. Verifies the tag matches `MARKETING_VERSION` and validates the changelog.
2. Runs tests.
3. Imports the Developer ID certificate into a temporary keychain.
4. `Scripts/sign-and-notarize.sh`: universal build, inside-out codesigning
   (Sparkle XPC services → Autoupdate → Updater.app → framework → app),
   notarization via `notarytool`, stapling, final `Keypress-<version>.zip`.
5. Generates `appcast.xml` with `generate_appcast` (signed with the Sparkle
   key).
6. Creates the GitHub release with notes extracted from `CHANGELOG.md`.
7. Commits the updated `appcast.xml` to `main` — only after the release asset
   is live, so updaters never see a dead download URL.

## Troubleshooting

- **Notarization rejected** — the workflow prints the full `notarytool log`.
  The most common cause is an unsigned nested binary.
- **Workflow failed after the tag was pushed** — fix the problem on `main`,
  then move the tag and re-run:

  ```bash
  git tag -f v0.2.0 && git push -f origin v0.2.0
  ```

  If the GitHub release was already created, delete it first:
  `gh release delete v0.2.0 --yes`.
- **`security: SecKeychainItemImport: … unknown format`** — the `.p12` was
  base64-encoded incorrectly; re-run `base64 -i DeveloperID.p12`.
- **No identity found** — the `.p12` export did not include the private key, or
  it is not a *Developer ID Application* certificate (e.g. it is *Apple
  Development* or *Developer ID Installer*).
- **Sparkle version drift** — `SPARKLE_VERSION` in `release.yml` should match
  the Sparkle version in `Package.resolved` (the CLI tools generate the feed;
  keeping them in sync avoids surprises).
