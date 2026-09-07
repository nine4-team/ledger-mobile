# Application Shell and Shared Controls

Status: canonical target; preserves existing UI capabilities, not Firebase coupling.

## Navigation and Shared Interaction

Preserve the Projects, Review, Search and Settings sections in the adaptive iOS
tab/macOS sidebar shell, with the existing application command entry points.
Navigation retains stable selected identities and real Account/Project/Inventory
context. Section changes dismiss the find overlay; returning to a detail cannot
reuse another Account's state. Authentication, explicit Account selection and
safe switching/logout remain governed by their owning specs.

Reuse backend-independent action menus, deferred menu-to-sheet presentation,
selection controls, find-on-page, form fields, date/select/toggle controls,
Save/Cancel, expandable sections, progress and error/retry presentation. Preserve
keyboard, focus, accessibility and platform behavior recorded in the unified
checklist. Each host determines eligible actions through the owning feature
contract, not generic Firebase field patches. No exact Swift component name,
unconditional sheet attachment or one-task-yield blank frame is a requirement.

Loading, empty, no-match, partial/stale, pending, unavailable, denied and failed
states stay distinguishable. Connectivity alone cannot prove local completeness
or successful synchronization. Protected media and counts follow the active
workspace's visibility policy. Source placeholders and Firestore diagnostic
screens are not target product features.

## Implementation and Verification

One shared shell/control implementation should serve the workflows; do not
rebuild navigation, forms or menus separately for each backend or feature.
Verify actual section/command navigation, menu-to-sheet transitions, keyboard
and accessibility behavior, scope changes, and loading/error recovery in the app.
Screenshots, compilation or helper tests alone do not prove the interaction path.

Existing navigation/performance logging is optional development support, not a
new telemetry product requirement. It may be retained or replaced as useful for
debugging responsiveness, without exposing protected data or adding a hosted
service. Preserve responsive interaction; do not freeze source logging details.

## Signed App Updates

Preserve the macOS Check for Updates command and the user's automatic-update
preference through the signed updater. A target staging build must not consume
the production Firebase app's update feed or replace that installation. Release
packaging, channel identity and update verification must be tested before an
authorized distribution; publishing is not authorized by a successful build.
An update or restart must preserve accepted offline operations and protected
media, or stop with an actionable compatibility/recovery result. Do not treat
an app update as permission to switch backend authority or discard local data.
