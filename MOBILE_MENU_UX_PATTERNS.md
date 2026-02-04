# Mobile menu UX patterns (reusable)

Use this as a quick guide for choosing *which* menu pattern to use on mobile, and the design rules that keep it feeling fast, clear, and consistent across the app.

## Choose the right pattern (rules of thumb)

### Use a **bottom sheet** for most menus (default)
Best for: kebab menus, sort, filter, “create…” pickers, bulk actions.

Pick a bottom sheet when:
- You want a universal pattern that works everywhere
- You might have more than ~6 options
- You may need sections (e.g., “Sort” + “Filters” + “Danger zone”)
- You care about one-handed reach and consistency

### Use an **anchored dropdown (popover)** only for small, simple menus
Best for: 3–6 quick actions with short labels.

Use it when:
- The menu is short, single-level, and won’t scroll
- It’s important that the menu appears next to the tapped control

Avoid it when:
- Options might scroll, wrap, or grow over time
- You need submenus, toggles, or multi-step choices
- The trigger is near screen edges (menus easily clip off-screen)
- You want a consistent one-handed experience (top-right is harder to reach)

### Use a **full screen** for “it’s basically a feature”
Best for: advanced filters, settings, long searchable lists, complex configuration.

If the user needs to read, search, or adjust many fields, a “menu” becomes a screen.

### Use a **centered modal** for focused tasks (not quick menus)
Best for: rename, confirm flows, editing a few fields.

Avoid using blur + centered modals for quick action lists. It feels heavier than needed and can slow things down.

## Common cases (what to use)

### Kebab (“more”) menu on an item or screen
Recommended default: **bottom sheet**.

Use a sheet especially when:
- You have destructive actions (Delete)
- You might add more actions later
- You want to group actions (e.g., “Move”, “Share”, “Archive”, “Delete”)

### Sort button
Recommended: **bottom sheet with a radio list**.

Rules:
- Show current selection clearly
- Apply immediately if it’s simple
- If it changes a lot of data, consider “Apply” and keep the sheet open while choosing

### Filter button
Recommended:
- Simple filters: **bottom sheet with toggles/checkboxes** (often apply immediately)
- Complex filters: **bottom sheet → “Advanced filters” → full screen**, with Apply/Reset

### Add button
Recommended:
- One primary action: navigate directly or use a primary button/FAB
- Multiple “create” types: **bottom sheet** (“Create…” chooser)

## Menu content rules (keep it usable)

### Keep choices tight
- Aim for **3–7 primary actions**
- Prefer clear labels over clever names
- Don’t hide important actions behind multiple layers

### Avoid nested submenus on mobile (if possible)
Submenus are harder to discover and slower to use. Prefer:
- Sections in a bottom sheet
- A follow-up screen for complex choices

### Put destructive actions last and make them obvious
- Place “Delete” at the bottom
- Use destructive styling (and keep it consistent)
- Require confirmation for irreversible actions, or provide Undo when safe

### Order by frequency
Put the most common actions near the top. Don’t order by “type” (edit/manage/etc.) unless it matches real use.

## Bottom sheet best practices (recommended universal component)

### Structure
- Optional title
- Sections (optional), separated with spacing/dividers
- Action rows with consistent height and alignment
- Optional “danger zone” section for destructive actions

### Interaction
- Dismiss on outside tap
- Support swipe-down to dismiss if you implement dragging
- On Android: Back button should close the sheet first

### Sizing & scrolling
- Avoid covering the whole screen for simple menus
- Keep content scrollable inside the sheet for long lists

### Tap targets & spacing
- Make rows easy to hit (aim for ~44pt+ height)
- Keep icons optional; never rely on icon-only meaning

### Accessibility basics
- Screen reader focus should move into the sheet when it opens
- Provide a clear “Close” action (outside tap + back is good; a close button is helpful for heavier sheets)

## Anchored dropdown best practices (if you use it)
- Keep it short (3–6 items)
- Never require scrolling
- Ensure it never renders off-screen (flip/shift as needed)
- Dismiss on outside tap + Back

## Centered modal best practices (for focused tasks)
- Use for confirmation, short forms, or important interruptions
- Keep copy short and specific (“Delete item?” not “Are you sure?”)
- Prefer “Cancel” + a single clear primary action

## Recommended standard for this app
- **Default**: bottom sheet for kebab, sort, filter, “create…”
- **Exception**: anchored dropdown only for very small, stable lists
- **Escalation**: full screen for advanced filter/settings complexity

