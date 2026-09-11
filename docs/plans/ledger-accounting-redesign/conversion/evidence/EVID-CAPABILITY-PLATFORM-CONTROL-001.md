# EVID-CAPABILITY-PLATFORM-CONTROL-001 — Platform, Transport, Release, and Migration Control

- Timestamp: 2026-08-31
- Class: static source/spec characterization and capability synthesis
- Repository baseline: `d83c64724fe4e92be27c62f425979bd30fcfc9bb`
  on `dev`; shared worktree was already dirty
- Production reads or mutations: none
- Target implementation/schema/RLS/Sync Stream changes: none
- Operator: Codex
- Primary artifact:
  `capability-dossiers/platform-transport-release-and-migration-control.md`

## Sources Reviewed

- Swift app root, Firebase/Google/Firestore/emulator construction, generic
  Repository/Batch abstractions, platform wrappers, diagnostics and test helpers;
- Xcode project/schemes, Info.plist, entitlements, Swift package resolution,
  Firebase configuration, build/release scripts and Sparkle/TestFlight inputs;
- MCP stdio/HTTP composition, config, Auth/account fallback, server instructions,
  schema/server-info, types/enums/errors/telemetry/format/note/pricing helpers;
- the entire legacy reverse Supabase-to-Firebase migration package and remaining
  Firebase repair/backfill/seed/rules/config/backup artifacts; and
- architecture environment, security, offline, migration, verification,
  observability and cutover documents plus applicable source specs.

## Method and Result

The review followed startup through dependency construction and environment
selection, every MCP transport/auth/capability boundary, release packaging and
hosting link, and both directions of existing migration tooling. It classified
which outcomes remain useful and which source/provider mechanics must be
isolated, redesigned, retired, or retained only for source evidence.

The dossier establishes one fail-closed environment manifest, a small target
composition root, Principal-bound MCP requests, versioned generated capability
contracts, structured correlation/redaction, reproducible release manifests,
provider-independent links, and a deterministic Firebase-export-to-Supabase
migration runner. It explicitly rejects reusing the reverse migration package
or creating a Firebase target adapter.

## Material Findings

- Current app root constructs Firebase-shaped services/contexts and platform
  side effects directly; macOS structured cache is memory-only.
- Generic Repository/Batch protocols abstract Firestore syntax, not Ledger
  behavior, and preserve arbitrary field/delete/path authority.
- MCP contains built-in production Account/User IDs, an environment Account
  fallback without request authentication, and a static bearer actor without a
  stable Principal.
- MCP instructions/schema/capabilities manually duplicate materially stale
  accounting and Quick Draft behavior.
- Current telemetry/errors are useful foundations but lack trusted environment/
  Principal/Account/operation/contract correlation and complete redaction/non-
  enumeration policy.
- No target-staging app identity/state namespace/refusal profile exists yet.
- Current release flows preserve TestFlight/Sparkle outcomes but lack one signed
  schema/contract/environment/reconciliation manifest.
- The existing `migration/` package reads Supabase and writes Firebase, guesses
  domain relationships and allows production/default Account behavior. It is
  source history only, not forward-migration code.

## Limitations

Installed-app environment behavior, entitlements/callbacks, release signing,
hosting/deep-link traffic, MCP deployment secrets/tokens, actual offline cache,
telemetry retention and existing migration executions remain unconfirmed by
runtime/production evidence. Target choices still depend on A-003/A-004/A-007/
A-015/A-016, O-022, isolated target infrastructure and release/migration
rehearsals.

This evidence supports target-independent platform, security, release,
observability, migration, and test design only. It does not authorize target
implementation, Firebase changes, production reads/mutations, migration,
release, or cutover.
