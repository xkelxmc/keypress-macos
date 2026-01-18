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
- macOS 14+ (Sonoma)

## Development

```bash
swift build              # Build
swift build -c release   # Release build
swift test               # Run tests
```

## Project Structure

```
Sources/
├── KeypressCore/    # Core logic (key monitoring, state)
├── Keypress/        # Main app (menu bar, overlay, settings)
docs/                # Documentation (vision, features, UI, technical)
```

## Documentation

- [docs/README.md](./docs/README.md) — Documentation index
- [docs/vision.md](./docs/vision.md) — Product vision
- [docs/features.md](./docs/features.md) — Feature specs
- [docs/technical/](./docs/technical/) — Architecture and tech details
