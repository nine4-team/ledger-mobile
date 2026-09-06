# EVID-CAPABILITY-APP-SHELL-001 — App Shell, Shared Presentation, and Test Support

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/app-shell-shared-presentation-and-test-support.md`

## Sources Reviewed

- all remaining automatically discovered Swift app files after the identity,
  media, Project/Client/reference, Item, Inventory/Transaction, Invoice/budget,
  reporting/search, Space/review, and platform dossiers;
- app shell, Auth/account/member screens, navigation routes, placeholder views,
  shared theme/components/forms/list controls and in-page find state;
- Item action coordinators, menus, editors, image grouping, list/filter/sort and
  display-only calculation helpers;
- native camera, document/PDF import, zoom/annotation and attachment display
  paths; and
- every remaining unit/integration test surface plus the legacy MCP Sale golden
  fixture.

## Method and Result

The review began from the machine-generated unclassified manifest set rather
than a hand-selected screen list. Each remaining source was inspected for SDK/
service construction, raw mutation authority, legacy accounting vocabulary,
identity/URL assumptions, local durability, readiness, authorization, and test
ownership. Reusable presentation outcomes were separated from domain decisions
and provider mechanics, then cross-checked against the previously reviewed
capability dossiers.

The result closes the final repository-discovered M0 classification block. It
preserves reusable UI/platform behavior, redesigns the shell and domain-aware
presentation against typed snapshots/intents, retires placeholders and raw
Item mutation coordinators, and keeps Firestore/legacy Sale tests only as source
evidence where appropriate.

## Material Findings

- Current shell views activate Firebase-shaped contexts/listeners and do not
  publish one complete Account workspace readiness contract.
- Auth/member UI imports Firebase directly or opens Firestore listeners, while
  some invite/member action failures are suppressed.
- Shared Item controllers perform arbitrary dictionary updates, direct
  relationship clears/deletes, concrete service construction and fire-and-
  forget error handling.
- Shared enums, menu builders, conflict flows and tests still encode target-
  invalid Sale/Payment-to-Business/direct transaction-link assumptions.
- List/grouping code is useful and deterministic but combines presentation with
  legacy fields and must never merge physical identity or select an accounting
  metric.
- Zoomable image and grouping paths use remote URL identity; target media uses
  stable Attachment IDs and durable local bytes.
- Firestore listener/relationship integration tests do not become target
  contracts; pure formatting, selection, navigation and accessibility behavior
  remains reusable.

## Limitations

No installed-app UX, accessibility, camera permission, large-project
performance, local-database readiness, target Auth, PowerSync stream, RLS,
offline restart, or operation-rejection behavior was executed. Those require
isolated target infrastructure, product decisions, implementation, fault tests,
and physical-device/platform verification.

This evidence supports M0 source coverage and target-independent presentation/
shell/test contracts only. It does not authorize implementation, Firebase
changes, production access, migration, release, or cutover.
