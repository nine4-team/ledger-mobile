# EVID-ATTACHMENT-CAPTURE-001 — Attachment Capture and Local-Durability Receipt Contracts

- Timestamp: 2026-09-01
- Class: implementation planning / provider-free attachment capture boundary
- Source baseline: `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` on
  `firebase`; the source worktree and released Firebase app remain unchanged
- Claimed target surfaces: `SWIFT-D8174F26DDD5`, `TEST-BA04EFCE369C`
- Slice dossier:
  `conversion/implementation-slices/attachment-capture-and-local-durability-receipt.json`
- Verification state: ready; behavioral implementation and tests have not begun

## Selection and Scope

The Phase 1 dependency audit selected the smallest honest attachment boundary:
the value and port contract that prevents a failed local byte save from looking
like accepted capture. The architecture already settles stable Attachment
identity, exact environment/Principal/Account/parent scope, raw bytes outside
structured sync, and a success receipt only after adapter-reported local
durability. It does not settle or prove the filesystem/provider implementation.

Exactly two target-only comment scaffolds are claimed in the provider-free core
and test targets. Current Firebase media services, models, queues, screens, MCP
tools, Storage rules/objects and migration scripts remain unadvanced.

## Why Named Gates Do Not Block This Slice

- A-003/A-004 and SPIKE-MED-001 gate the actual Supabase/PowerSync/Storage and
  encrypted physical-local implementation, not the provider-free receipt value.
- A-016 governs offline authorization and protected-data access duration; this
  slice records scope but opens no local database/file and grants no access.
- O-022 governs source-freeze and pending-work recovery at cutover; no logout,
  account removal, source queue or cutover behavior exists here.
- O-023 governs reference removal and permanent byte deletion. This slice has no
  detach, discard, cleanup, retention or delete operation.
- Allowed content/type/size and derivative policies remain open. The contract
  requires only nonempty bytes and exact size/checksum agreement; it approves no
  parent-specific content type, maximum size, derivative or metadata rule.

## Ready-Gate Contract

The dossier freezes six exact architecture requirements and requires:

- a non-Codable raw capture input with stable Attachment ID and exact
  environment/Principal/Account/parent scope;
- adapter-reported persisted-local-object evidence with opaque identity,
  positive byte count, SHA-256 and finite audit time;
- a receipt only when capture and persistence evidence match exactly;
- a canonical receipt fingerprint and decode-through-validation with no raw
  bytes, filesystem/object path, bucket, URL, token or credential;
- a narrow backend-neutral capture-store port that returns a receipt or throws;
  and
- stable deterministic validation/failure semantics that do not pretend to
  prove disk encryption, process/device restart durability or provider security.

Postgres, handlers, Data API, RLS, PowerSync, physical local persistence,
Storage/upload/verification/derivatives, display/cache, concrete app/MCP,
migration, observability and feature activation are explicit nonapplicabilities.

## Ready-Gate Verification

The two comment-only hashes are acknowledged through the reviewed media batch
and both surfaces are target-mapped. Every requirement is reciprocally covered
by planned domain, canonical-restart, rejection, deterministic media-fault and
exact-commit operational obligations.

The ready gate passed from the dedicated Supabase worktree on 2026-09-01:

- conversion sync/check/report — pass at 745 recorded / 730 discovered
  surfaces with only the same three documented retired-path warnings;
- capability and query generated checks — pass;
- residual generation/check — pass at 319 mapped / 164 residual / 43 blockers;
- M0 — pass; M1/M2 — expected blocks at the unchanged 2/164 prerequisites;
- `swift test --package-path LedgeriOS` — pass, the existing 88 tests in 19
  suites; the comment scaffold intentionally adds no executable attachment test;
- target environment and generated-contract checks — pass;
- macOS and generic iOS Simulator staging builds — pass; and
- `git diff --check` — pass.

That ready gate authorizes only the bounded provider-free implementation named
in the dossier.

## Permanent Limits

This ready gate and its later provider-free implementation cannot:

- claim bytes were actually written, encrypted, protected or retained across a
  process/device restart;
- accept a user capture in any current screen or MCP operation;
- upload, verify, derive, download, display, share, detach, discard or delete
  attachment bytes;
- choose content/type/size, metadata/EXIF, derivative, quota, cache, retention or
  O-023 policy;
- define Postgres/RLS/Sync/Storage/provider behavior or migrate source media;
- authorize hosted resources, production access, deployment, release or cutover.

No production read or mutation, Firebase implementation, provider connection,
hosted resource, migration, deployment or cutover occurred.
