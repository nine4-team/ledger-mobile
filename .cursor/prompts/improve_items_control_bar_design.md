# Improve Items List Control Bar Design

## Context
The Items list screen has a control bar above a search input. The control bar contains:
- A "Select all" checkbox on the left (always visible, enters bulk mode when clicked)
- Three action buttons on the right: "Add" (primary), "Sort" (secondary), "Filter" (secondary)

## Current Implementation
- File: `src/components/SharedItemsList.tsx` (lines ~400-453)
- The control bar uses `AppButton` components with basic styling
- Layout uses flexbox with gap spacing
- The search bar is directly below in `ListStateControls` component

## Goal
Improve the visual design and user experience of this control bar to follow mobile UI/UX best practices. Make it look polished, professional, and intuitive.

## Constraints
- Must maintain existing functionality (select all, add, sort, filter)
- Must work with the existing theme system (`useTheme`, `useUIKitTheme`)
- Should feel native to React Native mobile apps
- Consider spacing, visual hierarchy, touch targets, and visual feedback

## Deliverables
- Updated component code with improved styling
- Any necessary style adjustments
- Brief explanation of design decisions made
