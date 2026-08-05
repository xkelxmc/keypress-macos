# App Store screenshots

The generator renders ten deterministic Mac App Store frames per locale from the shipping SwiftUI components —
keycaps and keyboard frames, the pointer halo artwork, the pet sprite atlas, stacked history rows and the real
settings window. Each PNG is exactly 2880×1800 pixels (1440×900 pt at 2x).

The set ships in five locales — `en-US`, `de-DE`, `es-ES`, `fr-FR`, `ru` — fifty frames in total. Each locale has
one folder under `assets/appstore/generated/`, holding its ten frames and its App Preview video, so a folder is
exactly what one store listing needs.

Art direction and the scene plan live in `plan/appstore.md` under "Screenshots — 2.0.0 art direction & scene plan".

## Backgrounds are code-drawn

There are no background image assets any more. Every frame paints the "Neon Stage" in code: a near-black base, two
radial glows (indigo and cyan), an edge vignette and a seeded grain tile that keeps the gradients from banding. The
grain uses a fixed-seed PRNG, so re-running the generator produces the same pixels.

If `assets/screenshots/screenshot-bg-dark.png` / `screenshot-bg-light.png` are still lying around from the 1.x set,
they are unused and can be deleted.

## Generate screenshots

Run every scene in every locale from the repository root:

```bash
bun run screenshots
```

Render one locale, or selected scenes, by passing arguments directly to the executable:

```bash
swift build
.build/debug/Keypress --screenshot --language de-DE
.build/debug/Keypress --screenshot hero themes --language ru
```

`--language` takes a locale code or `all`, which is the default. List the available scenes:

```bash
.build/debug/Keypress --screenshot list
```

Scenes are rendered in store order; the headlines below are the en-US ones:

| # | id | stage | headline |
|---|----|-------|----------|
| 1 | `hero` | dark | Every *keystroke*, on screen. |
| 2 | `cursor-halo` | dark | Never lose the *pointer* again. |
| 3 | `pet` | dark | A *cat* that types with you. |
| 4 | `themes` | dark | Nine looks. Or build your *own*. |
| 5 | `stacked-history` | dark | Typing your viewers can *read*. |
| 6 | `placement` | dark | Exactly where it *belongs*. |
| 7 | `studio` | dark | A *studio*, not a settings sheet. |
| 8 | `customize` | dark | Tune every *key*. |
| 9 | `languages` | dark | Speaks your *language*. |
| 10 | `privacy` | dark | Nothing *leaves* your Mac. |

The word between asterisks is the accent word — it renders in italic serif in cyan.

Output is written to `assets/appstore/generated/<locale>/` as stable `NN-<scene-id>.png` filenames, next to that
locale's `preview-2.0.0.mp4`. Re-running the generator overwrites the existing files.

```text
assets/appstore/generated/
├── en-US/            01-hero.png … 10-privacy.png, preview-2.0.0.mp4
├── de-DE/            …
├── es-ES/            …
├── fr-FR/            …
├── ru/               …
├── preview-2.0.0-silent.mp4    en-US only
└── preview-2.0.0-master.mov    en-US only
```

The App Preview carries the same filename in every folder — the folder is what names the locale.

## Localization

- Every translated string lives in `Sources/Keypress/Screenshots/MarketingStrings.swift`, one table per locale.
  No user-visible copy is written inline in a scene any more.
- Deliberately untranslated, because they are product vocabulary that reads the same in every listing: the brand row
  ("Show KeyPress"), the theme names (dark, classic, …), the staged window titles (`demo.swift — Xcode`,
  `board — whiteboard`, `zsh — keypress`), the BONJOUR / ⌘Ü / ñ / Я keycaps and the EN DE ES FR RU chips.
- Frames 07 and 08 capture the real settings window, so the generator sets `config.general.language` per locale and
  the window renders in the app's own translations.

## How the frames are drawn

- Scenes never touch your own settings: each one builds throwaway `KeypressConfig` instances backed by the
  `dev.keypress.screenshots` UserDefaults suite, wiped before and after every render.
- Themes are selected through `appearance.keyboardThemeSelection` / `.pointerThemeSelection`, never the legacy
  keycap-style setters, which would fork the theme into `.custom`.
- The `studio` frame cannot go through `ImageRenderer` — `NavigationSplitView`, lists and materials are AppKit-backed
  and render as an "unsupported view" placeholder. That frame hosts the real settings window and captures the
  composited result instead. The capture takes the front-most claim outright, otherwise toggles, sliders and
  segmented pickers draw in their gray inactive colours; it also drops the hosting controller's sizing options,
  otherwise the split view's minimum height overrides the requested window size. Expect a run to steal focus briefly.
- That window is captured at 980×590 rather than the shipping 980×720 so its scroll edge lands in the gap below the
  Presentation card instead of slicing a control in half. The German, Spanish, French and Russian panes wrap the same
  way, so one height holds for every locale.
- It is parked far beyond the union of the attached displays, so it never appears on screen during a run. The window
  server still composites off-screen windows, which is what the capture reads; fading the window instead of moving it
  would land in the capture.
