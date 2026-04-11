# Visual Style (Desktop & Mobile)
Status: shipped (all visible work complete as of 2026-04-11)
Last updated: 2026-04-11

> **Note on web-parity scope:** The original spec treated the web app as the
> visual source of truth for colors and chrome. That framing is now stale —
> the iOS/macOS app's color palette is considered final on its own terms,
> and no cross-check against the web app is needed. The "Reference" and
> "Scope" sections below are preserved as historical context only.

> **Shipped**:
> - **Status colors** (2026-04-03) — Red/green/yellow + background variants brightened and normalized via asset catalog colorsets (commits dfa8e49a, 33eb5442). See StatusColors.swift and Assets.xcassets/Colors/.
> - **macOS border reduction** (2026-04-10) — Two coordinated changes in [Theme/](LedgeriOS/LedgeriOS/Theme/):
>     - `Dimensions.borderWidth` is now platform-aware — **0.5pt hairline on macOS**, 1pt on iOS. Every card, modal, form field, segmented control, and divider picks this up automatically (all ~50 call sites go through `Dimensions.borderWidth`).
>     - `BrandColors.softBorder` is now dark-mode adaptive on macOS via `NSColor(name:)` — gray-200 (#E5E7EB) in light, gray-700-ish (#3E4148) in dark. Previously hardcoded to the light value only, which read wrong against dark surfaces. iOS still uses `.separator`.
>   Net effect on macOS: cards and modals render as filled surfaces with a hairline edge rather than outlined boxes.
> - **Full typography swap** (2026-04-10) — [Typography.swift](LedgeriOS/LedgeriOS/Theme/Typography.swift) now routes every token through `.custom("AvenirNext-*"|"PlayfairDisplay-Regular", size:, relativeTo:)`. Dynamic Type scaling preserved via the `relativeTo:` argument.
>     - **Avenir Next** handles everything except screen titles — system font on all Apple platforms, no bundling needed. Weight map: h2/h3/button/buttonSmall/label/sectionLabel → DemiBold, body/small/caption/input → Regular.
>     - **Playfair Display** handles screen titles (`h1` at 26pt, Regular weight). Bundled as the Google Fonts variable TTF at [Resources/Fonts/PlayfairDisplay.ttf](LedgeriOS/LedgeriOS/Resources/Fonts/PlayfairDisplay.ttf). Wired into `project.pbxproj` with build file ID `FA7F0100000000000F0001AA` (Resources phase) and file ref ID `FA7F0200000000000F0001AA`. Registered for both platforms via `UIAppFonts` (iOS) and `ATSApplicationFontsPath = "."` (macOS) in [Info.plist](LedgeriOS/LedgeriOS/Info.plist). Runtime-verified via `CTFontManagerRegisterFontsForURL` — `PlayfairDisplay-Regular` resolves correctly (not falling back to Helvetica) on macOS. iOS uses the same registration path through `UIAppFonts`.
>
> **Icon call-site audit** (2026-04-11) — Walked all 75 `.font(.system(size: N))` call sites. 70 of them were SF Symbol icon sizing on `Image(systemName:)` (or on a Button container wrapping an icon) and were left alone — icons aren't text. The 5 text-rendering sites were migrated:
>     - [Badge.swift](LedgeriOS/LedgeriOS/Components/Badge.swift): 11pt semibold → new `Typography.badge` token (Avenir Next DemiBold 11pt).
>     - [NativeListControlBar.swift](LedgeriOS/LedgeriOS/Components/NativeListControlBar.swift), [TransactionAuditPanel.swift](LedgeriOS/LedgeriOS/Views/Projects/TransactionAuditPanel.swift): 10pt medium column/button labels → new `Typography.microLabel` token (Avenir Next Medium 10pt).
>     - [ProgressRing.swift](LedgeriOS/LedgeriOS/Components/ProgressRing.swift): dynamic `size * 0.28` percentage text → inline `.custom("AvenirNext-Bold", size: size * 0.28)` (parameterized, not token-worthy).
>     - [MakeCopiesModal.swift](LedgeriOS/LedgeriOS/Modals/MakeCopiesModal.swift): 48pt bold counter — dropped system-rounded design in favor of `.custom("AvenirNext-Bold", size: 48)` for brand-font consistency.
>
> Every site that renders text now routes through either a `Typography` token or an inline `.custom("AvenirNext-*", …)` call, so no Avenir-Next-branded surface is silently falling back to system fonts.

## Summary
The desktop app's color palette and UI chrome (borders, outlines, button styling) need to be updated to match the lighter, sleeker look and feel of the web app. The mobile app's colors are closer but the red specifically feels too dark/gloomy and should also align with the web app's palette. The app's typography across all platforms should adopt the 1584 Design brand fonts: Playfair Display and Avenir.

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

## Typography

The app should use the **1584 Design brand fonts** to create a more polished, upscale feel that aligns with the company's brand identity. Two fonts, used with restraint:

### Font Family

- **Playfair Display** — A high-contrast transitional serif designed by Claus Eggers Sørensen. Elegant, editorial quality. Used sparingly for maximum impact.
- **Avenir** — A geometric sans-serif designed by Adrian Frutiger. Clean, modern, highly legible at all sizes. The workhorse font for the app.

### Typography Hierarchy

| Role | Font | Weight | Usage |
|------|------|--------|-------|
| Screen titles | Playfair Display | Regular or Bold | The main title at the top of each screen ("Projects," "Inventory," "Transaction Detail," etc.) |
| Section headers | Avenir | Semibold | Labels above groups of content within a screen ("Recent Transactions," "Budget Summary," etc.) |
| Body text | Avenir | Regular | List item descriptions, detail view content, general reading text |
| Labels & captions | Avenir | Medium or Light | Field labels, secondary info, metadata, timestamps |
| Button text | Avenir | Medium | All interactive button labels |
| Navigation labels | Avenir | Medium | Tab bar items, sidebar navigation, menu items |
| Dollar amounts & numbers | Avenir | Regular or Semibold | All financial figures — consistent stroke weight matters for scannability |
| Input text | Avenir | Regular | Text the user types into form fields |

### Design Rationale

Playfair Display is reserved for screen titles only. This restraint is intentional — Playfair's high-contrast strokes look stunning at large sizes but lose their elegance as text gets smaller. By limiting it to the single biggest text element on each screen, it creates a branded, luxurious moment without competing with the functional text below it. Avenir handles everything else because its even stroke weight and geometric consistency make it effortlessly legible at any size, which is critical for an app where the user is scanning lists of transactions, reading dollar amounts, and navigating quickly.

### Scope

- **Desktop app**: Full typography update (both fonts)
- **Mobile app**: Full typography update (both fonts)
- **Web app**: Full typography update (both fonts) — all platforms should feel consistent

### What's Changing

- **All platforms**: Current system/default fonts → Playfair Display for screen titles, Avenir for all other text
- Font sizes, line heights, and letter spacing should be calibrated per platform to feel native while maintaining the brand identity [exact values TBD during implementation]

## Open Questions
- What are the exact hex/color values used in the web app for red, green, and yellow? [needs discovery from codebase or design files]
- What are the current desktop and mobile values for comparison? [needs discovery]
- Are there other colors beyond red, green, and yellow that need alignment (e.g., blues, grays, background colors)?
- **Toggle borders are likely a bug**: The black on toggles is inconsistent in thickness, which points to a rendering issue (something leaking through) rather than intentional design. Dev team should investigate the toggle component specifically for an errant background color or border.
- **Card/tile borders are intentional but should change**: The borders on cards and tiles appear to be consistent theming — not a bug, but a design choice that should be updated to match the web app's lighter treatment.
- Should the border treatment change apply to all UI elements universally, or are there specific elements where a border is appropriate?
- **Typography — font sizes**: What specific font sizes should Playfair Display screen titles use on each platform? (e.g., 28pt on mobile, 32pt on desktop?)
- **Typography — font licensing**: Playfair Display is open-source (Google Fonts), but Avenir is a commercial font (Linotype). Need to confirm licensing for app embedding. Alternative: Avenir Next (Apple system font, available on iOS/macOS natively) or Nunito Sans (open-source geometric sans with a similar feel).
- **Typography — web font loading**: For the web app, Playfair Display can be loaded from Google Fonts. Avenir will need to be self-hosted or an alternative used. Consider whether Avenir Next or a similar open-source alternative is acceptable for web.
