// Project Setup Use Case Tests READY scaffold
// Stable surface: TEST-BB8C5679BA31
//
// This leaf is intentionally comment-only at READY. No executable test, helper,
// adapter, import, or production declaration exists until implementation begins.
// The executable suite must close every obligation below without changing another
// file.
//
// PROJECTSETUPUSE-TEST-001 — admissible selections and exact one-call dispatch
//
// - Compile-time prove the use case is Sendable and consumes the existing Codable,
//   Equatable, Sendable ProjectSetupFormSelection and ProjectSetupFormPreparation.
// - Dispatch both exact represented-existing-Client and preallocated-new-Client
//   selections. Exercise Client/category quality independently across ready, partial,
//   and stale matching evidence, respecting the existing completeness invariant.
//   Every matching represented path must make exactly one create call; no ready-only
//   or complete-only policy is permitted.
// - Prove zero categories is valid and dispatched once. Separately preserve the
//   complete category set with absent, selected-null, explicit zero, large positive
//   Int64 Money, and mixed currencies. Allocation input order remains non-semantic
//   and canonical; no default, at-least-one, missing-as-zero, single-currency, or
//   32-bit-cap rule appears.
// - Assert exact stable Account/Project/Client/category identities, exact existing
//   ProjectDisplayName spelling, already-normalized optional description, and one
//   call for each admissible fixture.
//
// PROJECTSETUPUSE-TEST-002 — construction precedes dispatch and changed evidence is
// atomic
//
// - With one recording port, prove zero calls when an old selection is paired with
//   current preparation whose Account or any bound Client/category evidence changed:
//   row identity/order/insertion/removal, display/reference data, lifecycle/system/
//   kind/order/revision, query fingerprint, row/visible count, completeness, quality,
//   local data version, as-of time, or preparation evidence fingerprint.
// - Prove non-finite captured-at time is ProjectSetupFailure.invalidProjectCreatedAt
//   with zero calls.
// - Malformed preparation/selection encodings and fingerprint tamper remain closed by
//   their verified typed decoders before this API can be invoked. Do not invent a raw
//   decoding entry point merely to test the use case.
// - The application layer adds no Client/category lookup, authoritative-absence,
//   authorization, online, lifecycle, or UI admission decision.
//
// PROJECTSETUPUSE-TEST-003 — exact receipt lifecycle
//
// - For queued, applying, applied, rejected, superseded, and resolved, return an
//   OperationReceipt with the command OperationID and assert value-exact unchanged
//   return after exactly one call.
// - Return a different receipt OperationID and assert
//   ProjectSetupFailure.receiptMismatch after exactly one call.
// - A receipt is local operation evidence, not a Project row, authoritative result,
//   physical-durability proof, or server-commit assertion.
//
// PROJECTSETUPUSE-TEST-004 — reciprocal exact field ownership
//
// Compare each single-input variant with one baseline by flattened encoded leaf path
// and require the exact expected delta set. Equality-only or contains-only assertions
// are insufficient because coupled unintended changes must fail.
//
// - Account changes only draft.accountId, envelope.accountId, and fingerprint.
// - Project changes only draft.projectId, envelope.payload.projectId, subject.id, and
//   fingerprint.
// - Existing Client identity changes only draft.clientSelection.clientId,
//   envelope.payload.clientSelection.clientId, and fingerprint.
// - Existing-to-new Client selection changes kind and adds displayName in both draft
//   and payload;
//   changing the new Client ID or display name changes only the reciprocal selection
//   leaves and fingerprint.
// - Project display name and optional description each change only their reciprocal
//   draft/envelope.payload leaves and fingerprint.
// - Category identity, membership, allocation nullability, minor units, and currency
//   each change only the reciprocal draft/envelope.payload category-allocation leaves
//   and fingerprint; canonical array reordering alone changes nothing.
// - Operation changes only envelope.operationId and fingerprint.
// - Actor changes only draft.actorPrincipalId, envelope.actorPrincipalId, and
//   fingerprint.
// - Contract changes only draft.operationContractVersion,
//   envelope.contractVersion, and fingerprint.
// - Captured time changes only draft.capturedAt, envelope.clientCreatedAt, and
//   fingerprint.
// - Rebuild equivalent business selections against valid preparation-only evidence
//   changes—including readiness/completeness/version/as-of, Client display/audit, and
//   category name/kind/order/revision evidence that remains selectable—and assert no
//   command leaf changes. Selection/preparation fingerprints must not leak into the
//   command.
// - Each reciprocal variant makes exactly one call and contains the fixed empty
//   precondition collection and Project subject required by CreateProjectCommand.
//
// PROJECTSETUPUSE-TEST-005 — exhaustive error and cancellation boundary
//
// - Deliberately throw every ProjectSetupFormFailure from the port after capture and
//   assert exact preservation after one call:
//   accountScopeMismatch, clientNotSelectable, newClientIdentityCollision,
//   categoryNotSelectable, duplicateCategoryIdentity,
//   invalidPreparationFingerprint, invalidSelectionFingerprint,
//   preparationFingerprintMismatch, selectionFingerprintMismatch,
//   selectionPreparationMismatch, invalidEncodedPreparation, and
//   invalidEncodedSelection.
// - Deliberately throw every ProjectSetupFailure from the port after capture and
//   assert exact preservation after one call:
//   invalidClientSelection, negativeCategoryAllocation, duplicateCategoryIdentity,
//   invalidProjectCreatedAt, draftAccountMismatch, draftActorMismatch,
//   draftContractMismatch, draftPayloadMismatch, unexpectedPreconditions,
//   subjectMismatch, fingerprintMismatch, receiptMismatch, localAcceptanceFailed,
//   invalidEncodedCategoryAllocation, invalidEncodedDraft, and invalidEncodedCommand.
// - Deliberately throw CancellationError and assert cancellation remains cancellation
//   after one call. Throw an arbitrary error containing provider-sensitive detail and
//   assert exactly ProjectSetupFailure.localAcceptanceFailed after one call with no
//   raw detail exposed.
// - Retain the TEST-002 derivation failures as explicit zero-call counterexamples.
//
// PROJECTSETUPUSE-TEST-006 — diagnostics, canonical shape, and authority exclusions
//
// - Enumerate all twelve ProjectSetupFormFailure diagnosticCode mappings and all
//   sixteen ProjectSetupFailure mappings. Require their exact stable lowercase
//   underscore values; do not sample the taxonomy.
// - Assert the exact encoded CreateProjectCommand topology. Root keys are exactly
//   draft, envelope, subject, and fingerprint. Draft keys are exactly accountId,
//   actorPrincipalId, operationContractVersion, projectId, clientSelection,
//   displayName, description, categoryAllocations, and capturedAt. Envelope keys are
//   exactly operationId, contractVersion, accountId, actorPrincipalId,
//   clientCreatedAt, payload, and preconditions. Payload keys are exactly projectId,
//   clientSelection, displayName, description, and categoryAllocations. Subject keys
//   are exactly kind and id, with kind project. Preconditions are exactly empty and
//   fingerprint is one canonical SHA-256 string.
// - Existing Client selection keys are exactly kind and clientId; new Client selection
//   adds exactly displayName. A nil category allocation has exactly categoryId because
//   synthesized optional encoding omits allocation; a nonnil allocation adds exactly
//   allocation, whose Money has exactly minorUnits and currency. Assert exact omission
//   for nil as well as zero/positive values.
// - Assert the command contains no preparation/selection fingerprint, readiness,
//   completeness, version, as-of, row/count/query evidence, raw error, provider path,
//   URL, credential, token, source/target backend SDK, SQL, row policy, sync, UI,
//   default-selection, category-definition mutation, attachment/media, Project
//   lifecycle/delete/correction, Client merge/reassignment, accounting/history,
//   migration, hosted-resource, or production identity field.
//
// PROJECTSETUPUSE-TEST-007 — READY and actual-diff control
//
// - READY contains only these two comment scaffolds plus separately reviewed control
//   and evidence records. Implementation changes only these two claimed leaves.
// - NewProjectView and ProjectFormValidation plus their legacy tests retain
//   target_mapped status/content; ProjectService retains characterized status and
//   O-024/O-025 blockers. Verified presentation/operation dependencies remain
//   dependencies rather than newly promoted surfaces.
// - O-023/O-024/O-025/O-026 and every UI/default/category-mutation/media/provider/
//   migration/production exclusion remain unadvanced.
//
// PROJECTSETUPUSE-TEST-008 — immutable implementation verification
//
// - Separate exact READY and implementation commits must pass conversion traceability,
//   source/provider isolation, generated-contract checks, all focused suites, the full
//   target package with warnings as errors, repeatable project generation, macOS and
//   generic iOS Simulator staging builds, JSON validation, and clean tracked artifacts.
// - Only immutable exact-implementation CI may promote SWIFT-EE8576F5CD39 and
//   TEST-BB8C5679BA31 from implemented to verified. Deterministic in-memory tests do
//   not prove physical persistence, authorization, hosted behavior, or production.
