# Vision

## What is keypress-macos?

A macOS menu bar application that visualizes keyboard input in real-time with beautiful, skeuomorphic mechanical keyboard aesthetics.

## Target Audience

- **Content creators** — Streamers, YouTubers who want to show keyboard shortcuts during tutorials
- **Professionals** — Anyone doing screen sharing, demos, presentations where keyboard visibility helps
- **Educators** — Teachers demonstrating software, shortcuts, workflows

## Problem Statement

Existing keypress visualizers are either:
- Ugly with flat, basic UI
- Show keys as simple text labels instead of actual key visuals
- Require permanent screen real estate
- Lack proper animations that convey the "feel" of typing

## Solution

A premium-feeling visualizer that:
- Renders keys as realistic 3D mechanical keycaps
- Animates actual key press physics (top surface moves down)
- Appears only when typing, disappears when idle (no permanent window)
- Lives in the menu bar, completely unobtrusive
- Offers flexible positioning with visual configuration

## Design Philosophy

- **Invisible until needed** — No dock icon, no permanent window, just appears when you type
- **Premium aesthetics** — Skeuomorphic 3D mechanical keys, not flat boring rectangles
- **Minimal footprint** — Menu bar icon for control, overlay for visualization
- **Just works** — Enable and forget, with sensible defaults
