# EVID-MIGRATION-ENVIRONMENT-GUARD-001 — Migration Environment Guard

- Status: implemented; independent review and complete local gate passed; immutable implementation CI pending
- Date: 2026-09-06
- Environment: isolated provider-free migration target only
- Production/Firebase impact: none
- Slice: `migration-environment-guard`
- Claimed surfaces: `SWIFT-DB6A733FD6DE`, `TEST-2634F83E11F3`

## Historical READY Gate

The comment-only guard boundary passed the immutable READY gate at commit
`d281498bde31c27bd17879571ef67b42bfb1dc3d`, GitHub Actions run
`34056116157`. That checkpoint authorized only the provider-free local
implementation now present in this worktree.

## Current Implementation Candidate

`MigrationEnvironmentGuard.swift` now implements a package-visible fail-closed
preflight consistency primitive. It revalidates one canonical MigrationRunPlan
against an independently constructed package policy and requires exact agreement
on source snapshot and fixture bundle, validated target binding and all resource
hashes, Account-scope hash, repository revision, migration and sorted mapping
artifacts, four contract versions, dry-run mode, no-source/no-target credential
descriptors, and evidence-only disposition.

The only schema-v1 admissible tuple is:

`source_fixture + targetLocal + dry_run + sourceCredential:none + targetCredential:none`

An omitted request mode normalizes to explicit `dry_run`. Source production,
target staging/production, apply, credentials, missing/unknown/default values,
and any identity mismatch fail before a token is issued. Recursive duplicate-key
scanning precedes Foundation JSON decoding and detects duplicates at every
nesting level, including escaped-equivalent names.

For schema v1, Account-scope SHA-256 is exactly the direct lowercase SHA-256 of
the authenticated 32-lowercase-hex opaque fixture Account ID’s raw UTF-8 bytes,
with no prefix, delimiter, normalization, or framing. The golden digest is
`8cbab43dfd8e69379b761694cea3fd33f3fb9d4f29bf73a6a79b21fbac9cc9ed`.

Success returns a Codable evidence-only receipt plus a package-visible,
private-initializer, non-Codable process-local consistency token. Receipt decode
cannot recreate that token. Guard, policy, receipt, token, and factory remain
outside public client API. The guard accepts only immutable provider-free values
and exposes no provider, closure, handle, credential material, path, URL,
filesystem payload, database, network, Auth, Storage, or executor hook.

## Candidate Verification

Local focused verification passes:

- `swift test --package-path LedgeriOS --filter MigrationEnvironmentGuardTests`:
  seven tests passed;
- combined fixture and guard focused verification: 14 tests passed;
- `npm run target:environment:check`: passed with exact API, package visibility,
  private/non-Codable token, provider/import, application-link, and required-test
  checks; and
- `git diff --check`: passed.

The complete local batch gate also passed: all conversion, query-authority,
residual, target-environment and generated-contract checks; 26 MCP tests; the
complete 655-test Swift package across 97 suites; XcodeGen stability; macOS and
generic iOS Simulator staging builds; local Supabase schema lint; 374 pgTAP
assertions across 11 SQL suites; and the local RLS/RPC/read matrices.

The tests pin canonical request, policy, and receipt hashes; domain-separated
digest vectors; exact raw and canonical size ceilings; the fixture→policy→plan→
request→receipt path; every independently supplied identity category; target
resource hashes; all four contract versions; nested/root duplicate keys;
unknown/missing/noncanonical/tampered evidence; plan-size refusal; restart
evidence; and no-token rejection behavior.

The first independent implementation audit returned NO-GO. Two correction
rounds closed every finding, and the final read-only re-review returned GO with
zero P0-P3 findings. This document does not yet claim an exact implementation
commit, immutable implementation CI, or verified status.

## Explicit Limits

This primitive is consistency evidence, not operational trust or migration
authorization. A separately tracked sole-executor/composition slice must own an
independently trusted policy and require this opaque token plus an exact policy
match before provider construction. No such executor exists here.

This candidate cannot export, transform, load, reconcile, persist a journal,
sign or approve a plan, authorize apply, execute/resume/abort/rollback migration,
activate an environment, access hosted or production systems, change the
Firebase application, release, or cut over. O-022 and A-003/A-004 remain
unadvanced.
