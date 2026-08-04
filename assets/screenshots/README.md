# App Store screenshots

The generator renders nine deterministic Mac App Store frames from the shipping SwiftUI components — keycaps and
keyboard frames, the pointer halo artwork, the pet sprite atlas, stacked history rows and the real settings window.
Each PNG is exactly 2880×1800 pixels (1440×900 pt at 2x).

Art direction and the scene plan live in `plan/appstore.md` under "Screenshots — 2.0.0 art direction & scene plan".

## Backgrounds are code-drawn

There are no background image assets any more. Every frame paints the "Neon Stage" in code: a near-black base, two
radial glows (indigo and cyan), an edge vignette and a seeded grain tile that keeps the gradients from banding. The
grain uses a fixed-seed PRNG, so re-running the generator produces the same pixels.

If `assets/screenshots/screenshot-bg-dark.png` / `screenshot-bg-light.png` are still lying around from the 1.x set,
they are unused and can be deleted.

## Generate screenshots

Run every scene from the repository root:

```bash
bun run screenshots
```

Render selected scenes by passing one or more IDs directly to the executable:

```bash
swift build
.build/debug/Keypress --screenshot hero themes
```

List the available scenes:

```bash
.build/debug/Keypress --screenshot list
```

Scenes are rendered in store order:

| # | id | stage | headline |
|---|----|-------|----------|
| 1 | `hero` | dark | Every *keystroke*, on screen. |
| 2 | `cursor-halo` | dark | Never lose the *pointer* again. |
| 3 | `pet` | dark | A *cat* that types with you. |
| 4 | `themes` | dark | Nine looks. Or build your *own*. |
| 5 | `stacked-history` | dark | Typing your viewers can *read*. |
| 6 | `placement` | dark | Exactly where it *belongs*. |
| 7 | `studio` | light | A *studio*, not a settings sheet. |
| 8 | `languages` | dark | Speaks your *language*. |
| 9 | `privacy` | dark | Nothing *leaves* your Mac. |

The word between asterisks is the accent word — it renders in italic serif in cyan.

Output is written to `assets/appstore/generated/` as stable `NN-<scene-id>.png` filenames. Re-running the generator
overwrites the existing files. Only en-US is uploaded; other locales fall back to it.

## How the frames are drawn

- Scenes never touch your own settings: each one builds throwaway `KeypressConfig` instances backed by the
  `dev.keypress.screenshots` UserDefaults suite, wiped before and after every render, with the UI language pinned to
  English.
- Themes are selected through `appearance.keyboardThemeSelection` / `.pointerThemeSelection`, never the legacy
  keycap-style setters, which would fork the theme into `.custom`.
- The `studio` frame cannot go through `ImageRenderer` — `NavigationSplitView`, lists and materials are AppKit-backed
  and render as an "unsupported view" placeholder. That frame hosts the real settings window and captures the
  composited result instead. The capture activates the app and waits for the window to become key, so controls and
  traffic lights render in their active colours; it also drops the hosting controller's sizing options, otherwise the
  split view's minimum height overrides the requested window size.
- That window is captured at 980×590 rather than the shipping 980×720 so its scroll edge lands in the gap below the
  Presentation card instead of slicing a control in half.
- It is parked far beyond the union of the attached displays, so it never appears on screen during a run. The window
  server still composites off-screen windows, which is what the capture reads; fading the window instead of moving it
  would land in the capture.
