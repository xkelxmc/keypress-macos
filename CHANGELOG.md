# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Command zone** — both history modes now show modifiers, shortcuts, and system keys in a dedicated block with a repeat counter (⌘V ×3), positioned independently from the typed content
- **Input key sizing and tint** — Space, Enter, Backspace, and Tab can render wide or narrow (with per-key overrides) and carry a subtle tone that separates them from letter keys
- **Text echo timing controls** — Stacked mode exposes how long finished lines linger while typing and how quickly the text clears after a pause
- **Zone snapping in the positioning editor** — the two blocks stick to each other and to screen anchors, and can now be placed tight into screen corners

### Changed
- **Horizontal History is now a true typing ribbon** — keys appear strictly in typing order (Space, Enter, and Tab included), letters follow Shift and Caps Lock casing, every press gets its own keycap, and the row scrolls with a conveyor animation that adapts its speed to the typing pace
- **Stacked History now echoes real text** — typed characters render as large readable text on per-line plaques with inline ⏎ and ⇥ marks, Backspace genuinely erases, finished lines thin out behind the typing and the whole echo clears after a pause; nothing that left the screen ever comes back
- **Overlay appearance and exit are designed motions** — the block rises in and settles out as one rigid unit, the window frame stays frozen during the exit, and hiding waits for the animation to finish
- **Positioning editor treats zones as independent** — each history mode lays out its typed content and command zone separately per display, with a realistic three-line preview for Stacked mode
- **Keyboard settings page cleaned up** — dead toggles removed, the All Keys / Shortcuts Only choice and the function/special key filters scoped to the Latest mode where they act, and subtitles rewritten to describe the current behavior

### Fixed
- **History no longer scrambles typing order** — Space and other special keys stop jumping into the middle of the row, repeated letters stop flashing in place of each other, and a full row shifts as one motion instead of sliding single keys
- **Exit animation stutter on 60 Hz displays** — hiding the overlay no longer moves and resizes the window on every frame of the fade

## [2.0.0] - 2026-07-29

### Added
- **Animated Keypress Pet** — an original draggable cat with clean registered animations that types at your input speed, watches and hunts the cursor, sleeps, plays, and exposes independent behavior controls in Settings and onboarding
- **Premium first-run onboarding** — a cinematic introduction with original sound, an interactive local preview, explicit Input Monitoring setup, and guided keyboard and Cursor Halo configuration
- **Replayable setup tour** — unfinished onboarding can be resumed from Settings, while the complete experience can be replayed later without resetting saved preferences
- **Cursor Halo** — customizable shapes, layered translucent contours, colors, glow and responsive motion for movement, clicks, dragging and scrolling, with a live preview that matches the on-screen effect
- **On-screen positioning editor** — drag the real keyboard overlay directly on any connected display with snapping, reset, and cancel support
- **Native Studio settings** — a resizable sidebar interface with pinned live previews, grouped controls, and separate keyboard and pointer theme galleries
- **Stacked History** — an optional conversation-style keyboard history that groups continuous typing and keeps shortcuts readable
- **Input filters** — switch between all keys and shortcuts only, with independent controls for modifiers, function keys, and special keys
- **Expanded global shortcuts** — control the pointer halo, input mode, positioning editor, and overlay size without opening settings
- **Live localization** — English, Russian, German, Spanish, and French can be selected without restarting the app
- **Selected Displays mode** — mirror the keyboard overlay across multiple displays with a separate saved position for each one

### Changed
- **New app icon** — the Keypress cat peeking over a graphite mechanical keycap with a backlit K
- **App Store marketing set rebuilt** — ten screenshot scenes rendered from the shipping components with a shared visual system and deterministic settings-window capture
- **Keyboard presentation is now an explicit three-mode choice** — Latest, Horizontal History, and Stacked History use the same illustrated selector and animated preview in onboarding and Settings
- **Stacked History keeps the active shortcut anchored** — typed text and completed shortcuts grow around a stable key combination according to its screen position instead of shifting the overlay
- **Input Monitoring is requested only after a deliberate action** — onboarding explains why access is needed before opening System Settings, and the app remains disabled until setup is complete
- **Onboarding uses a consistent dark presentation** — the full-screen experience also respects Reduce Motion and Reduce Transparency accessibility preferences
- **Display preferences now use stable identifiers** — monitor reordering and reconnecting no longer point the overlay at the wrong screen
- **Status feedback now uses an independent HUD** — mode changes no longer move the keyboard overlay or use the old indicator-light style
- **Settings persistence is versioned** — existing preferences migrate into grouped, validated settings without changing the default keyboard behavior
- **Settings interactions stay immediate** — rapid slider and color changes are saved as one coalesced snapshot instead of blocking the UI on every step

### Fixed
- **App Store processing no longer rejects the binary** — the KeyboardShortcuts dependency is updated to 3.0.1, whose Arabic localization file no longer breaks Apple's bundle and signing analysis
- **Onboarding interactions stay responsive** — full-card hit targets, hover feedback, reliable ceremony skipping, and immediate Cursor Halo mode switching remove missed clicks and delayed controls
- **Keyboard previews match the selected behavior** — All Keys demonstrates ⇧⌘K, Shortcuts Only demonstrates ⇧⌘V, and replay animates each key sequentially from an unpressed state
- **Stacked History remains stable at every screen anchor** — mixed text and shortcut rows no longer drift, overflow their previews, duplicate the current chord, or align toward the wrong edge
- **Runtime input changes reconcile immediately** — content filters, timeouts, held modifiers, Fn shortcuts, missed releases, and display limits no longer leave stale or duplicated keys
- **Setup navigation no longer leaves empty sidebar space** — the temporary Setup destination disappears cleanly once permission and enablement are complete
- **Modifier and duplicate-key state is resilient** — evicted keys, missed releases, and permission transitions no longer leave stale keys visible
- **Cursor Halo stays attached to the pointer** — its dedicated listen-only event tap removes global-monitor lag, restores missed mouse releases, and resynchronizes after Space changes
- **Cursor Halo reaches every screen edge** — the transparent glow canvas is no longer constrained away from the menu bar edge

## [1.1.0] - 2026-07-28

### Fixed
- **Keys no longer stick on screen** — key monitoring is back on a dedicated listen-only CGEvent tap running off the main run loop, so key releases are never dropped behind UI work
- **Key shadows are no longer cut off at the anchored corner** — the overlay window reserves room for them instead of clipping whatever falls outside its bounds; the keys themselves stay in exactly the same spot on screen

## [1.0.0] - 2026-07-25

### Changed
- **Key monitoring now uses `NSEvent` monitors instead of a CGEvent tap** — same behavior, same Input Monitoring permission, no event-tap API
- **Auto monitor selection follows the pointer's screen** — replaces a frontmost-window lookup that needed the Accessibility API and never worked in the sandbox

### Added
- **App Store screenshot generator** — `bun run screenshots` renders seven 2880x1800 marketing frames from the real UI components

### Fixed
- **Screenshot generation no longer overwrites saved settings** — scenes now render against an isolated settings store instead of mutating the shared one

## [0.1.1] - 2026-07-19

### Added
- **Simultaneous keys in Single mode** — keys held down at the same time are now shown together instead of only the latest one

## [0.1.0] - 2026-07-19

### Added
- **Edge offset** — configurable horizontal (0-500px) and vertical (0-300px) offset from screen edges for all preset positions
- **Key visualization** — 3D mechanical keycaps with press animations, category-based colors
- **Three keycap styles** — Mechanical (3D), Flat (modern), Minimal (pill-shaped)
- **Press animation** — visual feedback when keys are pressed/released (toggleable for modifiers and regular keys)
- **Display modes** — Single (latest combo) and History (key stream)
- **Keyboard layout support** — works with Russian, German, and other layouts
- **Settings window** — 5 tabs: General, Position, Display, Colors, Style
- **Key style editor** — per-category color/style customization
- **Multi-monitor support** — auto-follow active window or fixed monitor
- **Auto light/dark mode** — follows system appearance
- **Global hotkey** — toggle with ⌘⇧K (customizable)
- **Toggle hint** — shows on/off state with hotkey reminder
- **Keyboard frame** — optional container around keys (Frame/Overlay/None)
- **Screenshot generator** — `--screenshot` CLI for promo images
