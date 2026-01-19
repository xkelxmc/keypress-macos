# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CRITICAL INSTRUCTIONS FOR AI AGENTS

### **ALWAYS READ FILES COMPLETELY - NEVER PARTIALLY!**

When working with this codebase, **YOU MUST ALWAYS READ FILES IN FULL** using the Read tool without limit/offset parameters. Partial file reading leads to critical errors and missed context.

## Project Overview

**keypress-macos** — A macOS menu bar app that visualizes keyboard input with skeuomorphic 3D mechanical key aesthetics.

- Shows pressed keys as realistic mechanical keycaps with press animations
- Appears only when typing, no permanent window
- Menu bar icon for control, click-through overlay for visualization
- Target: content creators, demos, screen sharing

For detailed specs, see [docs/README.md](./docs/README.md).

## Tech Stack

- Swift 6 with strict concurrency
- SwiftUI + AppKit
- Swift Package Manager
- Sparkle for auto-updates
- KeyboardShortcuts for global hotkeys
- macOS 14+ (Sonoma)

## Development

```bash
# Using bun scripts (recommended)
bun run start           # Kill, build, package, launch, verify
bun run start:test      # Same with tests
bun run build           # Debug build
bun run build:release   # Release build
bun run test            # Run tests
bun run lint            # SwiftLint
bun run format          # SwiftFormat
bun run check           # Both lint and format
bun run package         # Build Keypress.app
bun run stop            # Kill running instances

# Or directly with Swift/scripts
swift build
swift test
./Scripts/compile_and_run.sh
./Scripts/package_app.sh
./Scripts/launch.sh
```

After code changes, always rebuild and restart to test the actual app:
```bash
bun run start
```

## Coding Style

- **SwiftFormat + SwiftLint** — Run before commits: `bun run check`
- 4-space indent, 120-char lines
- Explicit `self` — Required for Swift 6 concurrency, do not remove
- Use `@Observable` (not `ObservableObject`/`@StateObject`)
- Use `@MainActor` for UI code

## Testing

- Swift Testing framework under `Tests/`
- Naming: `test_caseDescription`
- Always run `bun run test` before commits

## Versioning

Version is managed in `version.env`:
- `MARKETING_VERSION` — User-facing version (e.g., 0.1.0)
- `BUILD_NUMBER` — Incremental build number

## Project Structure

```
Sources/
├── KeypressCore/    # Core logic (key monitoring, state)
├── Keypress/        # Main app (menu bar, overlay, settings)
Scripts/             # Build, package, release scripts
Tests/               # Unit tests
docs/                # Documentation
plan/                # Implementation plan & notes (gitignored)
.github/workflows/   # CI configuration
```

## Git Rules

- **Never commit `plan/` folder** — it's in `.gitignore`, used for local planning only
- Commit `docs/` changes normally — that's the public documentation

## Scripts

| Script | Description |
|--------|-------------|
| `Scripts/compile_and_run.sh` | Full dev loop: kill, build, package, launch |
| `Scripts/package_app.sh` | Build .app bundle with Sparkle |
| `Scripts/launch.sh` | Launch existing app (kill previous first) |
| `Scripts/build_icon.sh` | Generate Icon.icns from PNG |
| `Scripts/release.sh` | Full release workflow |
| `Scripts/sign-and-notarize.sh` | Sign and notarize for distribution |
| `Scripts/make_appcast.sh` | Generate Sparkle update feed |
| `Scripts/validate_changelog.sh` | Validate CHANGELOG before release |

## Documentation

- [docs/README.md](./docs/README.md) — Documentation index
- [docs/vision.md](./docs/vision.md) — Product vision
- [docs/features.md](./docs/features.md) — Feature specs
- [docs/technical/](./docs/technical/) — Architecture and tech details
- [docs/icon.md](./docs/icon.md) — App icon source and build instructions
