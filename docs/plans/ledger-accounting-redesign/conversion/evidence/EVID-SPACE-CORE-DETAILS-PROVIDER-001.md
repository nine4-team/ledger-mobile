# EVID-SPACE-CORE-DETAILS-PROVIDER-001 — Space Core-Details Provider Implementation

- Date: 2026-09-05
- Class: isolated local implementation / independently reviewed executable slice
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on `firebase`; the Firebase checkout and released app were not changed
- Target branch: `codex/supabase-powersync-implementation`
- Frozen READY baseline: `9b62bec1403261a7d966c570af981da461d80f12`
- Slice dossier: `conversion/implementation-slices/space-core-details-powersync-provider.json`
- Claimed leaves: `CONFIG-C07E3326B896`, `CONFIG-55809460A27C`, `SWIFT-B762FCFD8525`, `TEST-33D5654E41CA`, `SWIFT-2335BBE3E8FD`, `TEST-FDF70607A5B4`, `SWIFT-C99453DE8B49`, `SWIFT-058F3155F97F`

## Implemented Outcome

An authorized local Account workspace can watch one exact active or archived Space, including a Space under an archived Project, and reconstruct its immutable scope, name, notes, revision, exact timestamps, ordered checklists, ordered checklist items and derived progress from encrypted PowerSync rows. The application model exposes honest waiting, partial, stale, ready, authoritative-absence and bounded-failure states, and the isolated staging app renders those states without providing a mutation action.

The implementation remains target-local and spike-prefixed. It reads no Firebase data, changes no Firebase code or resources, creates no hosted resource, imports no source row, registers no MCP tool and performs no production migration, release or cutover.

## Database and Authorization Boundary

- The existing seven-column `spike_spaces` destination relation, row bytes, active-only Data API policy/grant and destination Sync Streams remain unchanged. The sole base-table addition is a redundant `(account_id, id)` unique parent key required for exact same-Account child foreign keys.
- Separate `spike_space_core_details`, `spike_space_checklists` and `spike_space_checklist_items` relations own one-to-one detail and relational hierarchy evidence. Exact scope foreign keys, domain identifiers, unique presentation order, bounded UInt32 order and exact millisecond timestamps are enforced in Postgres.
- All three new relations enable and force RLS. PUBLIC, anon and authenticated have no direct relation privilege. Active-membership SELECT policies remain defense in depth for synchronization; there is no client writer, handler, RPC, trigger or SECURITY DEFINER path.
- The on-demand PowerSync stream contains exactly four Account/Space-bound queries for base Space, detail, checklists and checklist items. Every query derives signed identity and active Account membership and deliberately has no Space or Project lifecycle filter.

## Offline and Lifecycle Proof

The local provider binds every request to the owning Account and exact Space. It rejects foreign scope, malformed IDs or booleans, rebound child rows, duplicate physical/domain identities, duplicate order, nonpositive or overflowing revisions, and non-exact canonical text or timestamp evidence atomically.

Readiness is causal rather than inferred from cached rows. The provider subscribes to the exact current-process stream, records completion evidence for that retained epoch, then rereads local rows before producing a complete snapshot. Membership loss clears represented data and completeness; reactivation requires a new completion. Consumer cancellation and runtime close cancel, unsubscribe and join every owned row/status/subscription observer before the encrypted database closes.

The AppModel owns selection generations, clears prior content on selection/runtime loss, refuses noncooperative late updates and derives progress only from validated Core hierarchy. The runtime adapter forwards only the typed Space watch, and the view contains no edit, archive, Item, media, review, template, accounting or MCP behavior.

## Independent Review and Corrections

Independent database/Sync review found two implementation defects, both corrected and regression-tested:

- an unapproved `created_at <= updated_at` constraint contradicted the frozen contract's exact independent timestamps; the constraint was removed and pgTAP now proves reverse-ordered exact timestamps are accepted; and
- the least-privilege assertions omitted TRUNCATE, REFERENCES and TRIGGER; PUBLIC and anon checks now cover all seven table privileges.

The corrected database/Sync re-review returned GO with no P0–P3 finding. A separate offline/app review then found the missing encrypted startup/restart/invalidation proof and incomplete-progress rendering; after correction, its fresh re-review found no code P0–P3 issue. The root integrator independently inspected the delegated SQL, Sync, schema, tests and AppModel work, implemented the provider/runtime/app integration, expanded the executable tests and reran the complete local gates.

## Local Verification

- clean seeded local Supabase reset: passed all migrations and seed
- pgTAP: 340/340 assertions in 9 files, including 84 Space core-details assertions
- database lint at warning level with fail-on-warning: zero findings
- existing Space destination Data API regression runner: passed
- Space core-details provider: 9/9 tests passed twice consecutively
- Account workspace runtime: 19/19 tests passed
- Space core-details AppModel: 7/7 tests passed
- complete Swift package: 563/563 tests in 90 suites passed both normally and in CI's no-parallel mode
- target contract generation/check and MCP typecheck/tests: passed, including 26/26 MCP tests
- target environment/isolation checker: passed
- deterministic target project generation: passed
- isolated target macOS and generic iOS Simulator builds: passed

## Remaining Gates

Immutable exact-commit CI remains pending until the conversion ledger is synchronized and committed. `SPACECOREPROVIDER-TEST-004` remains planned until a real isolated authenticated PowerSync session proves exact authorized receipt and membership-revocation eviction.

A-003, A-004 and A-016 therefore remain proposed. This implementation does not authorize hosted Supabase/PowerSync resources, source import, Firebase changes, production access, migration, deployment, release or cutover. Product specs and the decision log remain product authority.
