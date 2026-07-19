# Privacy Policy

**Keypress** (App Store name: Show KeyPress)

Effective date: 19 July 2026

## Summary

Keypress does not collect, store, or transmit any data. There is no account, no
analytics, no telemetry, and no network access.

## What the app reads

Keypress visualizes the keys you press. To do this, macOS requires the **Input
Monitoring** permission, which you grant explicitly in System Settings → Privacy
& Security. macOS asks for it on first launch.

With that permission, the app observes keyboard events through a listen-only
event tap. Each event is used to draw a keycap on screen and is then discarded.

Specifically, Keypress:

- does **not** write keystrokes to disk, logs, or any file;
- does **not** send keystrokes, or anything else, over the network;
- does **not** share data with the developer or any third party;
- does **not** record, buffer, or reconstruct typed text beyond the handful of
  keys currently drawn on screen, which disappear after a short timeout;
- **cannot** modify or inject keyboard input — the event tap is listen-only.

## No network access

The App Store build runs in Apple's App Sandbox and is not granted the network
entitlement. It has no ability to make network connections, by design.

## What is stored on your Mac

Your preferences (position, colors, keycap style, display mode, hotkey, and
similar settings) are saved locally in macOS `UserDefaults`, on your own machine.
They never leave your device. Removing the app removes them.

## Children

Keypress is a utility for showing keystrokes on screen. It does not knowingly
collect any information from anyone, including children.

## Changes

If this policy ever changes, the updated version will be published at this same
address, with a new effective date.

## Contact

Questions or concerns: <https://github.com/xkelxmc/keypress-macos/issues>
