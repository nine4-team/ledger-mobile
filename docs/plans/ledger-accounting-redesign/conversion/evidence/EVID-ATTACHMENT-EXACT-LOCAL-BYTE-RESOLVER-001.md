# EVID-ATTACHMENT-EXACT-LOCAL-BYTE-RESOLVER-001 — Exact Local Attachment Byte Resolver

- Status: VERIFIED
- Date: 2026-09-06
- Base commit: `f71e75a9c15091a45fb10727d1ec78a27d6f2fc5`
- Exact implementation commit: `a35926c8fb07be56e218a87926bbc1934c8cb813`
- Immutable Actions run: `34019611549`
- Environment: dedicated target worktree only
- Production/Firebase impact: none

## Outcome

The implemented slice adds one backend-neutral operation that accepts a complete,
already-issued `AttachmentLocalDurabilityReceipt` and returns its exact protected
local bytes only after the receipt's queue evidence and ciphertext reverify. It
operates only inside an already-open Account runtime and is read-only,
non-consuming, offline-first infrastructure—not upload, rendering, workspace
authorization, retention, deletion, migration, or release behavior.

## Authority and Selection

Architecture 03 requires captured attachments to display their local bytes
immediately and makes local protected bytes authoritative until remote
verification. Architecture 04 requires a narrow backend-neutral attachment port.
The verified attachment provider already owns encrypted storage, immutable
path-free receipts, queue evidence, AES-GCM metadata authentication, byte-count
and SHA-256 reverification. The missing capability is exact receipt-addressed
access through the lifecycle-owned Account runtime; the existing FIFO uploader
candidate is not a display resolver.

Independent candidate audit rejected every remaining product workflow because
of unresolved policy and selected this target-local prerequisite. A separate
read-only implementation preflight confirmed the existing vault and lifecycle
lease are sufficient and identified the precise store/runtime/control seams.

## Frozen Boundary

- Require the complete immutable receipt; never accept only `AttachmentID`.
- Reject namespace mismatch before any row lookup.
- Require an exact queue row, valid persisted evidence, and byte-for-byte receipt
  equality before asking the vault for bytes.
- Reuse the vault's descriptor-relative, bounded AES-GCM/count/SHA verification.
- Resolve any requested receipt rather than the first FIFO upload candidate.
- Keep queue state, count, order, pending work and `ps_crud` unchanged.
- Hold one existing finite runtime lease through lookup and decryption; close
  waits for it, while concurrent/post-close admission refuses.
- Return only `Data` or a bounded non-sensitive contract failure.

## Implemented Surfaces

Owned executable leaves:

- `SWIFT-82312CAAB02F` — `LedgerTargetCore/AttachmentLocalByteResolution.swift`
- `TEST-CF9AB8ADB530` — `LedgerTargetCoreTests/AttachmentLocalByteResolutionTests.swift`

Frozen affected/shared touchpoints, whose existing primary owners remain intact:

- `SWIFT-F850F907B87F` / `TEST-CE5D3D0516D1` — attachment store/provider tests
- `SWIFT-75CFE285AF37` / `TEST-8D6A15063B2D` — lifecycle owner/runtime tests
- `SWIFT-548A8A928FAE` — public target runtime facade
- `CONFIG-81235587F306` — exact target-environment/public-surface guard
- generated Xcode project, manifest, classification, coverage, audits, evidence
  index, execution state and tracker

## Required Proof

The eight dossier tests cover exact non-FIFO selection, restart, full namespace
and receipt rebinding, malformed rows, missing/corrupt/link/wrong-key evidence,
non-consuming queue/Sync behavior, cancellation, close drainage, public-surface
containment, complete tests/builds and immutable CI.

Local focused proof now passes:

- two provider-free contract tests;
- all 17 attachment durability/provider tests, including four resolver cases;
- all 21 Account-workspace runtime tests, including two resolver lifecycle cases;
- the deterministic target-environment/public-surface guard.

Complete local proof also passes: all 577 Swift tests in 91 suites, 374 pgTAP
assertions across 11 files, strict database lint, 26 MCP tests, conversion/query/
environment/contract controls and both staging builds. The first concurrent
macOS/iOS build attempt caused an Xcode DerivedData lock; the macOS build and
serial iOS rerun both passed.

Independent executable review initially found three P2 issues: cancellation was
collapsed by both database helpers, scope-first rejection was not proven before
all database access, and the corruption test truncated ciphertext instead of
proving equal-length AEAD tampering while all local/Sync state stayed unchanged.
The corrected implementation preserves cancellation, adds a deterministic
pre-database checkpoint, flips one ciphertext bit without changing length, and
asserts queue identity/state/count plus zero `ps_crud` writes. Final re-review is
GO with no remaining P0/P1/P2 finding. Conversion check reports 996 recorded / 981
discovered / zero errors / three known warnings; the M0 and environment gates and
diff check pass.

Exact implementation commit `a35926c8fb07be56e218a87926bbc1934c8cb813`
passed all three immutable workflow jobs in Actions run `34019611549`:
conversion state and traceability, the isolated target environment, and local
Supabase provider slices. The slice is therefore `verified` at this boundary.

## Explicit Non-Advancement

A-016 remains the production-facing workspace activation/offline authorization
lease gate. A-003/A-004 and SPIKE-MED-001 remain hosted/physical-device gates.
O-023 remains the retention/deletion decision. This slice adds no Postgres, RLS,
Data API, Sync Stream, Storage, remote fallback, uploader, renderer, AppModel,
SwiftUI, MCP, Firebase, source data, migration, release, production access, or
cutover authority.
