# Bug Report: Item Screen Layout Clipping & "Gray Bar" Artifact

## Issue Description
On the Item Detail screen (`app/items/[id].tsx`), the top content (specifically the "Untitled item" title) is being clipped. Additionally, there is an unwanted gray/chrome rectangle visible.

## Visual Symptoms
- The title "Untitled item" is partially cut off at the top.
- An extra gray rectangle appears, described by the user as making things look "stupid".
- When attempting to push content down via header styling, the gray bar reportedly appeared *below* the content, indicating a layering or layout flow issue.

## Context
- **Screen Component**: `src/components/Screen.tsx`
- **Header Component**: `src/components/TopHeader.tsx`
- **Item Screen**: `app/items/[id].tsx`

## Failed Attempt
- **Attempt**: Modified `TopHeader.tsx` to use `position: 'relative'` and explicit padding/height instead of `getScreenHeaderStyle`.
- **Result**: User reported "nothing has changed visually" or that the gray bar was "below the content".
- **Status**: Reverted.

## Task
Investigate the `Screen` component's layout logic, specifically how `contentPaddingTop` is calculated in `src/components/Screen.tsx` vs. how `TopHeader` is rendered. The header might be rendering twice, or the `AppScrollView` content container styling is conflicting with the absolute positioned header.

Fix the layout so:
1. The title is not clipped.
2. No extraneous gray bars appear.
3. The header (back button/menu) remains functional and correctly positioned.
