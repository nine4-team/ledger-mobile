// Project Setup Use Case READY scaffold
// Stable surface: SWIFT-EE8576F5CD39
//
// This leaf is intentionally comment-only at READY. It freezes one provider-free
// application boundary over the verified Project setup presentation and operation
// contracts without claiming executable behavior.
//
// Required composition
//
// - Define one public Sendable ProjectSetupUseCase generic over a Sendable
//   ProjectSetupOperating implementation. Do not introduce another form, selection,
//   draft, command, failure, receipt, readiness, query, or operation-port type.
// - Its initializer accepts only the injected ProjectSetupOperating dependency.
// - Its async throwing execute call accepts exactly:
//   ProjectSetupFormSelection, the current ProjectSetupFormPreparation, ProjectID,
//   OperationID, PrincipalID, OperationContractVersion, and a captured-at Date.
//   It returns OperationReceipt, not a Boolean, Project row, optimistic projection,
//   or assertion of authoritative server commit.
// - First derive CreateProjectCommand by calling the existing selection command
//   function with the current preparation and all caller-supplied metadata. Command
//   construction must finish before the operation port can be invoked.
// - Invoke ProjectSetupOperating.create exactly once with that derived command,
//   validate the returned receipt through CreateProjectCommand.validate, and return
//   the exact receipt unchanged. Every LocalOperationState remains meaningful and
//   unchanged: queued, applying, applied, rejected, superseded, and resolved.
//
// Offline evidence and admission boundary
//
// - The existing selection/preparation fingerprint is the complete local evidence
//   boundary. Exact current evidence is revalidated before dispatch; an old selection
//   cannot dispatch after any bound Client/category evidence changes.
// - Matching represented evidence remains admissible for every independently valid
//   ready, partial, or stale Client/category quality. This use case must not add a
//   ready-only, complete-only, online-only, lifecycle, permission, or other read-
//   admission policy.
// - Partial or stale evidence never proves authorization or authoritative absence.
//   A represented active Client/category can be selected locally; a new Client ID
//   not represented in incomplete evidence can be submitted, but an unrepresented
//   collision remains a trusted authoritative-apply concern.
// - Preparation fingerprints, readiness, completeness, versions, timestamps, row
//   counts, and display/reference metadata are derivation evidence only. They must
//   not be added to CreateProjectCommand. Rebuilding a selection against changed but
//   still valid current evidence may yield the same command when business intent is
//   unchanged.
//
// Error boundary
//
// - Preserve CancellationError as cancellation.
// - Preserve every ProjectSetupFormFailure and ProjectSetupFailure without wrapping
//   or translating it, including either type deliberately returned by the port.
// - Map every other error thrown by the port to
//   ProjectSetupFailure.localAcceptanceFailed. Raw provider detail cannot cross the
//   application boundary.
// - Keep derivation outside the port-error catch. In particular, a catch-all must not
//   relabel an unexpected command-construction invariant failure as local acceptance.
// - Derivation failure makes zero port calls. Receipt mismatch is
//   ProjectSetupFailure.receiptMismatch after exactly one port call.
//
// Product meaning preserved from the verified dependencies
//
// - One setup intent binds stable Account, Project, and existing-or-new Client
//   identity. Client display text never owns or authorizes the relationship.
// - The complete duplicate-free category set preserves absence, selected null,
//   selected explicit zero, and selected positive non-negative Money. Zero selected
//   categories is valid; no default selection, at-least-one rule, missing-as-zero
//   coercion, single-currency rule, or source 32-bit amount cap may be added.
// - The existing ProjectDisplayName value is passed exactly. The already-canonical
//   optional description stored by ProjectSetupFormSelection is passed exactly.
// - Existing/new Client selection and represented active non-system category checks
//   stay owned by ProjectSetupFormPresentation; trusted current authorization stays
//   owned by the later authoritative handler.
//
// Strict exclusions
//
// This leaf owns no UI/form steps, copy, loading, dirty/no-op, validation display,
// cancel/success dismissal, navigation, defaults, category creation or mutation,
// Project edit/archive/restore/delete, Client rename/archive/merge/reassignment,
// initial lifecycle policy, attachment identity/bytes/hero upload/reference/removal/
// retention, Project/Client/category row, optimistic projection, physical local
// durability, retry scheduler, authorization, membership, audit assignment, server
// handler, Postgres/Data API/RLS/PowerSync/provider/Auth behavior, app/MCP wiring,
// Firebase decoding or migration, hosted resources, production access, release, or
// cutover. O-023, O-024, O-025, and O-026 remain open and unadvanced.
