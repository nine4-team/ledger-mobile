# Quick Draft macOS navigation regression

## Fix

Project Quick Draft navigation uses a stable draft ID and a presentation flag,
matching regular Item Detail. The destination defers mounting its state-heavy
content until after the navigation push. It reuses a matching ambient project
context or activates its own context for the draft's project, also following
Item Detail. The parent route no longer injects its live project context.

The deferred wrapper alone, and then the wrapper plus ID-based presentation,
still reproduced the hang while direct parent-context injection remained.
Samples showed a busy main thread in SwiftUI/AttributeGraph reconciliation.
The complete combination above passed the manual checks below; this does not
establish that any one of these changes alone is sufficient.

## Manual verification — 2026-09-18

- Plain `LedgeriOS`, Debug, macOS build succeeded.
- Used the existing `DerivedData-test-primary` app instance (PID 94714).
- Production Firebase; process environment had no `USE_FIREBASE_EMULATORS` flag.
- From a project's Items tab, opened the previously failing wall-art Quick
  Draft. Detail rendered and remained responsive (click plus accessibility
  inspection completed in approximately 3.8 seconds).
- Opened Select Space: the project's named spaces appeared.
- Closed the picker without selecting and navigated back successfully.
- Opened a second draft (woven baskets); detail and its project-space picker
  also rendered successfully.
- CPU settled to 0.0% while idle rather than remaining near 100% as in the
  failed candidates.
- No draft fields or space assignments were changed. Only one Ledger app
  process was running; this verification did not launch another instance.
- `git diff --check` passed.

Not verified in this pass: iOS runtime, persistence of a changed assignment,
conversion/merge/delete, inventory/search entry points, or release packaging.
