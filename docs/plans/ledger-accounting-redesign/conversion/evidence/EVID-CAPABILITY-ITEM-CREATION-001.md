# EVID-CAPABILITY-ITEM-CREATION-001 — Unified Item Creation, Link, and Legacy Capture

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/unified-item-creation-accounting-link-and-legacy-capture.md`

## Sources Reviewed

- Item and ProtoItem models, services/protocols, validation, local tag/SKU
  extraction and current Firestore relationship helpers;
- full Item, separate Quick Add, proto review/card, Project Items, Item detail,
  shared list/card and transaction-first Item-entry app paths;
- MCP Item and quick-draft modules and every granular non-media Item/proto tool;
- existing Swift and MCP tests for Item validation, Codable source shapes,
  CRUD/bulk behavior, list/detail/cards, category/Transaction invariants, price
  normalization, physical-copy naming and quick-draft promotion/media;
- current Item/proto Firestore rules, Item-related Functions, generated query
  catalog and prior backend/media characterization;
- `proto-item-capture.md`, `items.md`, `data-model.md`, `item-entry-flow.md`,
  `add-existing-items.md`, D-018–D-025, O-016–O-023 and the hard-cutover/A-017
  architecture guardrails; and
- source profiler/export and migration plans for Item/proto/Transaction/
  Invoice/lineage/media correlation.

## Method and Result

Static source and call-site evidence was reconciled with current tests, product
authority, rules, Functions, MCP tools, query evidence and migration/cutover
constraints. The dossier separates user outcomes from Firebase mechanics,
classifies 52 previously unclassified surfaces, defines target-neutral
CreateItem/Link/read-model/migration contracts and names domain, offline,
security, concurrency and reconciliation tests without choosing target tables.

The review also corrected a material guidance contradiction. The target app
does not dual-read Firebase proto records. Current Firebase proto behavior stays
unchanged before hard cutover; immutable snapshots are repeatedly imported into
isolated target staging; the final freeze/import/reconciliation transforms each
proto into one target Item or a blocking quarantine result. D-025, the canonical
Item/proto specs and traceability now say this explicitly. O-027 records the
minimum name/photo/note validation decision that the two current forms disagree
about.

## Material Findings

- Current Item intake has two persistence identities and writers: real Items
  and ProtoItems. The target retains fast capture but writes one real Item.
- Full Item and Quick Add have contradictory minimum validation and price
  requirements. Target implementation cannot silently choose either one.
- `NewItemView` and MCP quick-draft promotion independently assemble Item,
  Transaction, lineage, acquisition, conversion and media effects. These are
  duplicated application/domain operations, not reusable persistence adapters.
- Some linked create paths return generated Item objects before asynchronous
  Firestore commit and default to printing commit failures; several UI callers
  suppress later conversion/delete errors.
- Current quantity behavior is contradictory and one app path can create N
  records while leaving quantity N on every record. The approved target stores
  quantity on one Item; explicit physical copy is a separate operation.
- Project Items groups by Item-versus-proto storage type rather than derived
  accounting relationships. Generic set/clear Transaction actions conflate
  Link, correction and association repair.
- Business-paid creation/promotion can manufacture a Project Purchase in
  current code. Target Business-paid Link creates one open Item occurrence and
  no Project Transaction before Invoice collection.
- Current Item hard delete and proto/media cleanup vary by caller and lack the
  target dependency, paid-history and retention policy.
- Local extraction is a useful advisory capability and can be preserved without
  granting it authority to Link, merge or create financial evidence.
- Existing proto statuses, hints and candidate IDs are source evidence only;
  importer/reconciliation must not promote them to confirmed accounting facts.

## Limitations

Production Item/proto counts, field variants, conversion correlations,
quantity anomalies, overloaded Transaction relationships, orphans, media
references and unresolved candidates remain unconfirmed until the fail-closed
read-only profile runs. Final target mapping also depends on the occurrence/
Invoicing dossier and O-015. This evidence supports target-independent command,
port and test design only. It does not authorize Postgres DDL, Supabase RLS,
PowerSync Streams, Firebase refactoring/adapters, production reads/mutations,
or migration.
