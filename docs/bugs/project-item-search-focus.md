# Project item search focus and shrinking results

## Fix

Project Items uses SharedItemsList's own scroll container with controls in its
top safe-area inset. Quick Drafts are leading list content; project rows remain
single-column, group expansion remains inline, and the existing project bulk
selection bar is retained. Search/filter calculations are unchanged.

The old search binding scrolled to the page top on every text change. Merely
removing that call reproduced blank results after pasting from deep in the list.
Targeting the pinned Items header also reproduced a freeze. Flattening nested
lazy rows alone did not fix it. A process sample showed repeated macOS layout
and text-end-editing work. Keeping the editor outside the lazy scrolling content
resolved the reproduced cases without scroll commands in the text binding.

## Verification (2026-09-18)

- macOS and iOS Simulator builds succeeded.
- Focused filter/sort and search suites: 77 tests passed.
- Production-backed macOS QA in Kristin Witzenman's project (623 items):
  - Scroll to the bottom, open search, paste an exact full item name: matching
    item visible, field retains focus, no freeze.
  - Purchased status filter active: type `m`, `a`, then `ttress` without
    refocusing; matching results remain accessible.
  - Paste exact name with that filter, append nonmatching text, replace with
    matching text: empty and populated states work; focus remains in search.
  - Clear search: full results and Quick Drafts return.
- Confirmed the QA process did not enable Firebase emulators.

Manual QA was on macOS; iOS was compile-checked. The user's exact pasted name
and original filter were unknown, so this covers the reproduced failure class.
