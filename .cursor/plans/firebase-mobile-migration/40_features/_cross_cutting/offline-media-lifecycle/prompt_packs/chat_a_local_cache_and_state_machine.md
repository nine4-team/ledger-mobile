# Prompt Pack — Chat A: Local cache + attachment state machine contract

## Goal
Implement Phase A of the offline media lifecycle:

- durable local media cache + local media record
- consistent attachment reference + minimum UI state machine (`local_only`, `uploading`, `uploaded`, `failed`)
- selection-time gating that integrates quota/guardrails

## Required reading (ground truth)
- Spec: `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`
- Architecture: `OFFLINE_FIRST_V2_SPEC.md`
- Guardrails subcomponent (referenced by the spec): `40_features/_cross_cutting/ui/components/storage_quota_warning.md`

## Outputs (required)
- Implement/define the local media cache persistence layer (platform-appropriate; do not assume a fixed storage limit).
- Implement/define a durable local media record (metadata: size, localUri/path, checksum if used, timestamps, owning scope).
- Implement/define attachment references on domain entities such that UI can render:
  - `local_only` (local exists, not uploaded)
  - `uploading` (scheduled/in-progress)
  - `uploaded` (remote-backed)
  - `failed` (upload failed)
  - Contract note (GAP B):
    - Persisted attachment refs are `AttachmentRef` with explicit `kind: "image" | "pdf"` (see `20_data/data_contracts.md`).
    - Do not persist transient upload state on Firestore domain entities; state is local + derived (see `40_features/_cross_cutting/offline-media-lifecycle/feature_spec.md`).
- Integrate selection-time validation with quota/guardrails without redefining thresholds/copy (use the guardrails spec).

## Constraints
- Offline-first: selection and local linking must succeed without network.
- Firestore-native offline persistence is the baseline; UI must render from locally-available state when offline.
- No “subscribe to everything” patterns; do not introduce large listeners.
- Do not invent new product capabilities or rename domain concepts.

## Edge cases (must be explicit)
- User cancels after local save: how the local blob/record is handled (must not leak).
- App restart after selection but before upload begins: `local_only` must still render correctly.
- Multiple attachments per entity (e.g. `transaction.receiptImages[]`, `space.images[]`) vs singular fields (e.g. `businessProfile.logo`).
- Large file selection blocked by guardrails: required user-visible behavior is “warn at getting full; hard block near-full” per the guardrails spec.

