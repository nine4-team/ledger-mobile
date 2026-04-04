# Visual Style (Desktop & Mobile)
Status: modify
Last updated: 2026-04-02

## Summary
The desktop app's color palette and UI chrome (borders, outlines, button styling) need to be updated to match the lighter, sleeker look and feel of the web app. The mobile app's colors are closer but the red specifically feels too dark/gloomy and should also align with the web app's palette.

## Reference
The **web app is the visual reference** for both desktop and mobile. The web app's colors, borders, and overall styling represent the desired look and feel.

## Scope
- **Desktop app**: Color palette changes AND border/outline styling changes (both need work)
- **Mobile app**: Color palette adjustment only (the red specifically; overall styling is already better than desktop)
- **Web app**: No changes — this is the source of truth

## How It Works
The app uses a set of status/accent colors (red, green, yellow) throughout the UI for indicators, labels, buttons, and other elements. These colors should feel light, dimensional, and modern — not heavy or harsh.

UI elements like buttons, tiles, toggles, and cards should have soft, subtle edges rather than thick, dark outlines. The overall impression should be sleek and clean, not boxed-in or heavy-handed.

## What's Changing

### Staying the Same
- The web app's color palette and styling (already correct — this is the target)
- The mobile app's overall layout and styling approach (just the color values are adjusting)

### Changing

#### Desktop App
- **Status colors (red, green, yellow)**: Current colors → match the web app's lighter, more dimensional versions of these colors
- **Borders and outlines on UI elements**: Harsh, thick black borders around buttons, tiles, toggles, and cards → softer, lighter borders (or no borders) matching the web app's treatment. The current thick black borders look almost accidental — like a debug stroke showing through.
- **Buttons**: Current heavy-bordered style → sleeker style matching web app
- **Tiles/cards**: Current heavy-bordered style → lighter, more dimensional style matching web app
- **Toggles and controls**: Thick black border that appears inconsistent in thickness — likely a rendering bug where a background or border color is leaking through, not intentional styling. Fix: remove the errant black and match the web app's clean toggle treatment
- **Background tones**: Should match the web app's lighter feel [needs discovery — exact current vs. desired background colors TBD]

#### Mobile App
- **Red accent color**: Current "sophisticated" red that reads as dingy/gloomy → match the web app's red, which feels brighter and more alive
- **Green accent color**: Review against web app and align if different [needs confirmation — may already be fine]
- **Yellow accent color**: Review against web app and align if different [needs confirmation — may already be fine]

### Adding
- Nothing new

### Removing
- The thick black border/outline treatment throughout the desktop app

## Design Direction
The user described the desired feel as: lighter, dimensional, sleeker. The current desktop app feels heavy and harsh by comparison. Think of it as going from "outlined/stroked" to "filled/dimensional" — the shapes and elements should feel like they have depth and lightness rather than being contained by dark outlines.

Not silly at all — color and visual weight have a huge impact on how an app feels to use day-to-day.

## Open Questions
- What are the exact hex/color values used in the web app for red, green, and yellow? [needs discovery from codebase or design files]
- What are the current desktop and mobile values for comparison? [needs discovery]
- Are there other colors beyond red, green, and yellow that need alignment (e.g., blues, grays, background colors)?
- **Toggle borders are likely a bug**: The black on toggles is inconsistent in thickness, which points to a rendering issue (something leaking through) rather than intentional design. Dev team should investigate the toggle component specifically for an errant background color or border.
- **Card/tile borders are intentional but should change**: The borders on cards and tiles appear to be consistent theming — not a bug, but a design choice that should be updated to match the web app's lighter treatment.
- Should the border treatment change apply to all UI elements universally, or are there specific elements where a border is appropriate?
