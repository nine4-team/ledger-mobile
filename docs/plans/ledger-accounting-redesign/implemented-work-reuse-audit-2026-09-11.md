# Audit of work already implemented: replacement versus reuse

Date: September 11, 2026. One-time assessment, not a new progress tracker.
Initial snapshot: branch `codex/supabase-powersync-implementation`, HEAD `505dc2bb`;
comparison baseline `fe018501d67cc84b6f140b2645b8a8149ea5c4f6` (verified merge base).
Completion review at `ca68d793f193463fd191d272891d02cf85b7c5c4`: see
"Completed review and implementation decisions" for current dispositions.
Initial Purchase/gallery status and counts below are historical, not current claims.
All source inspection occurred in the Supabase worktree. No Firebase checkout,
production access, code removal, new test run, commit, or implementation change.

## Answer

**The concern is substantiated. We did not consistently preserve existing UI
implementation while replacing its backend dependencies.** We built a separate
target app shell and subsequently reconstructed existing interactions inside it.
The gallery is not the only example. The checklist editor and thumbnail image
processing also have existing reusable implementations that the target bypasses.

This does **not** establish that the entire conversion, or a measurable number of
weeks, was wasted. The new backend, offline durability, authorization, accounting
relationships, and migration work address real requirements. Much of that work
can remain behind reused UI. The evidence does not establish the cheapest recovery
path for every screen, nor whether retrofitting a particular replacement now is
cheaper than retaining it. Sunk cost is not a reason to continue duplicate UI by
default, or a reason to delete otherwise useful code indiscriminately.

The principal failure is **a missing reuse decision at the boundary between
existing UI and new data/application code**. Behavioral checklists verified that
new controls reproduced behavior, but did not require a reason for implementing
those controls again. More efficient CI waiting does not solve this problem.

## Scope and evidence standard

- Enumerated every current Swift file in the target app, application-model,
  Core, PowerSync, composition, migration and support modules, plus target MCP
  sources and SQL migrations. Distinguished comment-only files from code.
- Compared concrete original/target implementations for the gallery, image
  loading/thumbnail generation, Item list/cards/detail, checklist editing,
  Project setup, reports/sharing, vendor parsing, and PDF image extraction.
- Inspected architecture decisions, build-source membership, enforcement scripts,
  and introduction/follow-up commits to explain the observed implementation path.
- The appendix accounts for every target-app file. The other implementation
  families are classified below by responsibility, not certified line by line.
  "Required" means its responsibility is required, not that every abstraction,
  line, or test has been proved minimal, correct, complete, or production-ready.
- Excluded unbuilt future features from duplication claims. Did not run another
  product audit, native suite, or architecture redesign exercise.

Classes: **A** approved product redesign; **B** necessary backend/offline/security
integration; **C** duplicated reusable presentation/utility responsibility;
**U** replacement or additional machinery not sufficiently justified by this
review; **R** actual reuse; **H** diagnostic/test harness; **N** not implemented.
Mixed classes identify the boundary inside a file, not permission to delete it.

## Findings and disposition

| Implemented area | Classification and evidence | Recommended disposition |
|---|---|---|
| Image viewer, zoom, paging, pinning | **C + B.** Target `DownloadedItemImagesView.swift` and `DownloadedImageZoomSurface.swift` implement presentation independently of original `Components/ImageGallery.swift`, `ZoomableScrollView.swift`, `PinnedImagePanel.swift`, and `Logic/MediaGalleryCalculations.swift`. The original zoom component loads URLs, resolves `gs:` addresses, and uses ImageCache; it is not a drop-in backend-free component. Its gesture/layout code nevertheless does not require Firebase. | Retain authorized byte loading/cache and image-reference contracts. Evaluate extracting/adapting the existing image presentation with injected bytes/loading and callbacks before any further polishing of the replacement. Do not simply reconnect Firebase URL/cache access. |
| Checklist editor controls | **C + B.** Original `Modals/EditChecklistModal.swift` accepts a Space and an `onSave: ([Checklist]) -> Void` callback, owns a local draft, and already adds/removes/reorders/edits checklist rows. Target `SpaceChecklistEditorStagingExerciseView.swift` builds those controls again. New revision validation, durable acceptance and rejection handling belong behind that presentation boundary. | Reuse/adapt the original editor and row presentation; map its draft to the new command and surface pending/rejection states. Stable identities and draft semantics need checking, but a whole second editor is not established as necessary. |
| Thumbnail pixel resizing/JPEG encoding | **C + B.** Original `Services/ImageThumbnailGenerator.swift` is explicitly a pure utility; it already uses ImageIO for orientation-aware downsampling/JPEG output. Target `AppModel/ItemCardThumbnailGenerator.swift` implements that kernel again and adds content identity, complete-decode, byte limits and immutable derivative validation. | Keep the stronger validation and derivative/reference model. Consolidate or adapt the pixel-processing kernel; do not discard the new integrity checks or reproduce the old inferred-storage-path scheme. This is a small concrete duplication, not evidence that all thumbnail work was wasted. |
| Item lists/cards/filter controls/detail sections | **U + B + A.** `DownloadedItemsView.swift` builds a new list, grouping/selection/filter controls and detail view. Existing `SharedItemsList`, `ItemCard`, `GroupedItemCard`, `FilterMenu`, `SortMenu`, `ItemsTabView` and `ItemDetailView` already supply substantial presentation. They are coupled to old Item types, Account/Project contexts and sometimes Firestore listeners. Canonical accounting associations and unknown/restricted data states genuinely change their inputs. | Keep typed authorized projections and redesigned accounting interpretation. Before expanding this UI, compare extracting original presentation against maintaining the replacement. No claim that the entire original screen can be linked unchanged. No evidence currently justifies wholesale visual reconstruction as a migration requirement. |
| Project setup and Project/Client browsers | **A + B + H; U for final UI replacement.** New Client identity/selection, atomic Project/category setup and offline pending states require new logic. Original `NewProjectView` already has the name/category/budget wizard but embeds services. Target browser views explicitly present diagnostic status, IDs and retries. | Keep command/model/provider logic and useful harnesses. Adapt existing Project presentation where compatible; redesigned Client selection must follow approved specs. Do not mistake the diagnostic browser for a justified final replacement of the original app navigation. |
| Space browsing/detail/referenced navigation | **B + H; U for final UI replacement.** New local readers, stable scoped routes, archived references and rejected-operation handling are required. Target views/compositions reconstruct Space browsing/detail around them. Original `SpacesTabView`, `SpaceDetailView` and checklist presentation exist. | Preserve scoped route/application state. Reuse original presentation where feasible. Keep harness-only controls out of the intended shipped UI and do not expand them merely to accumulate feature coverage. |
| Account selection, access gate, pending work, profile | **B + H; U for replacing Settings presentation.** Offline reopening, Account removal, pending-work retention and account-isolated cache access differ materially from Firebase SDK behavior. Read-only `AccountBusinessProfileView` does not implement a replacement for all original Account settings. | Keep security/session machinery and small validation surfaces. Integrate their results into the existing shell/settings when the composition is settled; do not call missing settings features implemented because profile text is visible. |
| Property Management and Client Summary report data | **A + B.** Core snapshots/readers now use physical Items, canonical accounting and authorization, including explicit incomplete/unknown evidence. Legacy aggregators use old Item/Transaction relationships. A-023 and A-033 explain the changed authority. | Keep canonical calculation/read boundaries, parity evidence and restricted-data handling. Reusing old renderers must not reintroduce their old accounting calculations. |
| PDF generation, report preview and native sharing | **B with documented technical choice; U for full presentation replacement.** A-023 explicitly chooses CoreText pagination from immutable snapshots and protected export lifetime. Original `ReportPDFSharing` uses WebKit and a fixed 612×792 capture, delayed rendering and temporary URLs. The target handles multi-page content and destination lifetime. Original report styling and layout components are not reused. | Do not label the new renderer or safe handoff wholly unnecessary. Retain the documented correctness improvements. Separately recover original report presentation where needed rather than treating new plain rendering as equivalent visual fidelity. Original sharing code is not safe to substitute without checking completion/cleanup requirements. |
| Amazon/Wayfair text parsing | **R + B.** `LedgerTargetProject.yml` directly compiles five unchanged original files: AmazonInvoiceParser, WayfairInvoiceParser, InvoiceMoneyParsing, InvoiceDateParsing and PdfTextExtractor. `LocalVendorPDFParser` maps their results to the target review model. | Keep. This is a demonstrated example of the intended strategy: reuse the mature algorithm and adapt its boundary. |
| Vendor PDF review and product thumbnails | **B; U for review-screen replacement.** A-027 provides a bounded local-review rationale. The new thumbnail extractor uses PDF image placement/SKU anchors and rejects ambiguous evidence; original `PdfImageExtractor` uses text-gap/layout heuristics. These are not equivalent algorithms. | Keep parser reuse, immutable extracted evidence and conservative thumbnail association pending ordinary correctness verification. Review reuse of original import rows/forms separately. Do not call this an unnecessary parser rewrite; no accounting confirmation implementation is implied. |
| Shared filtering/selection/form helpers | **B/A + U.** New typed scope, cursor and unknown-evidence contracts have real jobs. Some pure presentation calculations overlap existing `ListFilterSortCalculations`, `SelectionCalculations`, `ItemCardCalculations` and formatting helpers. Existing filter code treats missing image/Transaction data differently from the target. | Keep authoritative semantics. Do not copy old predicates wholesale or infer that every new helper is required. Consolidate identical pure operations opportunistically; do not start another generic query framework. |
| Postgres, PowerSync, operations, security and migration | **A/B**, with individual minimality not established by this audit. See family coverage below. These responsibilities cannot be fulfilled by leaving Firebase listeners/writers unchanged. | Retain pending ordinary correctness/completeness review. This audit supplies no justification for deleting the backend implementation because duplicate UI exists. |
| Current uncommitted Purchase and gallery changes | Purchase code: **B**, partial/unverified. Gallery patch: **H**, test-only repair attempt, still failing one local repetition. | Preserve both. Gallery scheduling is paused. Do not accept the patch, continue tests, commit unrelated Purchase work, or silently discard either as an outcome of this audit. |

## Why this happened: evidence rather than intent attribution

1. **Isolation established a new app root.** Commit `2da54304` created
   `LedgerTargetStagingApp` as an environment-diagnostic shell. Its original copy
   explicitly said it could not authenticate, sync, upload, migrate or contact
   production. Separate build identity and no Firebase linkage were reasonable.
   They did not require replacing backend-independent UI.
2. **The shell became the place to implement user workflows.** Later commits
   added `*StagingExerciseView` and `*StagingExercise` components for each provider
   slice. The current project compiles the target app directory plus only the five
   original parser files listed above. It does not compile the original gallery,
   checklist editor, Item cards, or app design-system components.
3. **At introduction, rules protected provider boundaries, not concrete reuse decisions.**
   A-001 calls for domain-oriented ports; A-017 says Firebase is a migration source
   and the released app remains untouched. Neither says to rebuild gestures or
   presentational controls. The workflow method and AGENTS say to reuse working
   code, but contain no concrete requirement to identify the original component
   and justify replacing it before implementing a new counterpart. AGENTS and the
   method have since been corrected; this review supplies concrete plan choices.
4. **The build checks rewarded the chosen implementation shape.**
   `scripts/check-target-environment.mjs` verifies explicit staging view/model/
   runtime-adapter names and wiring (for example Space browsing and Project/Client
   browsing). It rejects Firebase linkage, appropriately, but does not evaluate
   whether an existing presentation component could be extracted. These checks
   made the new shell structurally well-checked, not economically justified.
   They do not categorically prohibit reuse: the parser exception proves it.
5. **Behavior restoration then generated more work.** Commit `6355430e` added
   a new 127-line gallery while correctly introducing protected image reads.
   Subsequent commits `7e0383c4`, `5721c40f`, `48e4dd96`, `45799fb0`, `b18a0c31`
   and `998329bd` restored zoom, pinning, swipes, full-screen controls, stable
   layout and reachable controls. Those are real implementation/repair rounds
   around a separate viewer, not just speculative future scope.
6. **Recent optimization addressed the expense after this boundary error.**
   Quiet waiting reduced repeated monitoring. Choosing gallery reliability as
   the next sample nevertheless assumed the replacement should continue. That
   assumption was not justified first. The current test patch changes tests,
   not the original gallery, and cannot settle which viewer we should use.

Inference: the practical path became "build an isolated target workflow and
restore its behavior," rather than "reuse existing presentation and replace the
data/application seam." That interpretation is supported by code and commit
sequence; the repository cannot establish an agent's private reasoning.

## Completed review and implementation decisions

Review completed at `ca68d793f193463fd191d272891d02cf85b7c5c4`.
The initial findings/file classifications below are retained as historical
evidence; these dispositions resolve their U entries. This is a necessity/reuse
review of implemented responsibilities, not a line-by-line correctness audit.
Every target-app file is accounted for; other modules are reviewed by the
responsibility families below. No claim that every backend function is minimal.

The existing checklist's affected execution records now carry these choices in
`reusePlan`; its shared `implementationGuidance` covers harnesses and unused
infrastructure. No behaviors, acceptance checks, failures or product blockers
were removed. No new recurring audit or parallel catalog is introduced.

| Area | Decision and implementation boundary |
|---|---|
| Gallery | **ADAPT original ImageGallery/ZoomableScrollView/PinnedImagePanel and MediaGalleryCalculations.** Inject stable target image identity, authorized image/load state, and explicit save/pin callbacks. Original ZoomableScrollView loads URLs; ImageGallery defaults Save to ImageSaveHelper. Remove those dependencies from the extracted presentation; never reconnect Firebase/cache URL access. Keep target protected bytes, revocation, cancellation and export policy. Stop polishing the separate gesture implementation. |
| Checklist | **ADAPT EditChecklistModal layout/controls.** Its draft and save callback are reusable, but index-based ForEach identity and legacy Space input must become stable IDs and explicit bindings. Keep the target model's revision-bound save, pending/rejection and disabled-control behavior. Do not import legacy service models just to compile UI. |
| Thumbnail | **CONSOLIDATE only the pixel kernel when that area is next changed.** Original ImageThumbnailGenerator already transforms orientation and encodes JPEG. Keep target source hash/size, complete-decode/JPEG end-marker checks, dimension bounds and explicit derivative identity. Original small-image nil behavior and inferred filename helpers are not target semantics. No standalone cleanup prerequisite or second cache. |
| Items | **ADAPT original cards/list controls/detail layout; KEEP target controller/data.** ItemCard already takes price/category/location labels and selection/action callbacks; replace hidden AccountContext invoice/Space lookups with authorized inputs. SharedItemsList's embedded mode still imports Firestore/owns listeners; ItemDetailView constructs old services and Transaction mutators. Extract presentation, not those controllers. Preserve target unknown/restricted accounting/image states and exact money; do not fabricate a legacy Item with default financial values. Stop expanding replacement-screen presentation. |
| Projects/Clients/setup | **ADAPT ProjectCard, MultiStepFormSheet/FormField and NewProjectView step content.** Inject authorized hero images instead of ProjectCard's FirebaseImage, and target budgets instead of old aggregation. Reuse wizard presentation while retaining atomic ProjectSetup and represented Client selection. Client identity is genuine redesign, not permission to rebuild shared forms. Diagnostic IDs/readiness/retry displays remain harness-only. |
| Spaces/navigation | **ADAPT SpacesTabView/SpaceCard/SpaceDetailView presentation.** Replace ProjectContext list/count inputs and service containers with existing target scoped readers/routes. Keep reference/archive/unavailable states, observer cancellation and navigation identity. Stop growing staging navigation into a second final app shell. |
| Account/settings | **ADAPT SettingsView/AccountView presentation.** Replace AuthManager/AccountContext/MediaService/AccountsService inputs and actions with target authorized profile/logo and pending-work-aware commands. Keep access gates, learned-removal markers, encrypted retention and logout policy. AccountBusinessProfileView is a readback harness, not completed Settings/profile editing. |
| Vendor PDF review | **ADAPT DraftItemsList/DraftItemRow bindings and controls.** They already implement inclusion, description, quantity/price, SKU/attributes and thumbnails. Use existing target stable document/row identity, missing-value validation and lifetime handling. Keep five reused parsers and A-027 conservative thumbnail association. Do not import legacy accounting writers or filtered-index thumbnail attachment. |
| Reports | **KEEP documented renderer/data replacements; ADAPT presentation.** A-023 justifies paginated CoreText and owned sharing payload instead of fixed-page WebKit/temporary URL capture. Keep A-033 eligibility. Reuse original report controls/style tokens and translate applicable ReportPDFStyles layout into this renderer without old aggregators or remote assets. Client Summary financial-total policy remains unresolved; physical detail is not authority to invent totals. |
| Pure list helpers | **KEEP live query contracts; no generic expansion.** SharedListQueryPresentation symbols occur in 41 other source files (including the synthetic fixture), covering scope, sort/cursors/readiness and data versions. Reuse identical SelectionCalculations/ItemCardCalculations/formatting where useful; legacy missing-image/Transaction predicates do not match target unknown states. No separate consolidation campaign. |
| Seven generic files | **FREEZE; do not expand or wire in merely to use them.** TypedEditDraft, ScopedRouteResolution, OperationalHealth, PrivacySafeTelemetry, LedgerReleaseManifest, ValidatedTargetComposition and DeterministicTargetTestSupport have no application symbol consumers found, only tests. Keep files intact; no mass cleanup project. A future concrete need may justify a small part, not adoption of the framework. |
| Remaining backend/models/MCP/migration | **KEEP required responsibilities and actual integrations.** SQL handlers/RLS, streams, local stores/readers/RPCs, replay, account/byte storage, target models, report consumers and migration/reconciliation cannot be supplied by unchanged Firebase services. Family coverage below is not certification of each wrapper. Comment-only placeholders are not features and are not instructions to fill them in. |
| Tests/build glue | **KEEP risk evidence; ADAPT structural assertions in the reuse batch.** Staging-name checks must not force replacement UI to remain. Preserve no-Firebase linkage when changing source membership. No tests or CI were needed or run for this documentation review. |

Consumer evidence: enumerated public types/aliases in the eight named generic
Swift files and searched repository Swift/JS/TS/build YAML, including hidden
configuration, excluding .git. The seven frozen families' symbols appear only
in their own test files; TestSupport also appears in Composition tests.
This is static-reference evidence, not runtime reachability proof. Required
security/isolation/release responsibilities remain requirements; these particular
unused implementations are not automatically mandatory.

The post-505dc2bb diff adds bounded Purchase read/security/sync/consumer changes
and CI/process documents, no new presentation files. Purchase is now committed
and scoped-verified at `6f9efa2e` in `item-linked-purchase-read`, superseding
the partial/uncommitted labels below. Its overall CI run was cancelled after
required backend checks passed; not a green whole-app gate. The unrelated dirty
gallery test remains unaccepted and untouched.

### Next proposed batch — not started or authorized by this review

Integrate original gallery presentation with the existing protected image
provider under `downloaded-item-browsing-and-detail`. Limit changes to image
input/callback extraction, original gallery/zoom/pinned presentation, source
membership and directly affected tests. No Item cards, thumbnail cleanup, schema,
payment commands, generic frameworks or other screens in that batch.

Finish when target image viewing uses the extracted original presentation and
preserves the existing image-gesture/control/export/protected-read checks.
Retire the superseded viewer only within that separately authorized integration
after verification. Use focused existing image/model/security checks plus targeted
iOS/macOS interaction checks: native gestures and loading identity actually change.
No DB suite absent data changes. Broad UI stays at the normal integration gate.

**Stopping rule met:** every formerly uncertain implemented family has a
keep/adapt/freeze decision and an owning checklist record or shared guidance.
Existing product blockers remain in place. This is not feature completion,
authorization to delete working code, or a forecast of savings. No additional
architecture/product audit is a prerequisite to the proposed batch.

## Limits on the amount of wasted work

The target app directory contains 43 Swift files / 6,638 physical lines at this
snapshot: seven are comment-only placeholders, and many others are adapters,
diagnostic views or fixtures rather than duplicate product UI. There are 104
commits touching that directory after the baseline. Neither count measures waste,
tokens, developer time, or completed features. The two gallery implementation
files alone total 644 lines; that is replacement surface, not 644 proven wasted
lines. No defensible "weeks wasted" or savings percentage follows from this audit.

The concrete finding is narrower and actionable: at least gallery presentation,
checklist editing presentation, and the thumbnail pixel-processing kernel were
implemented separately despite reusable predecessors. Whole-screen Item reuse
and other replacements have additional unresolved justification questions.

## File-level coverage of the target app directory

Paths below are relative to `LedgeriOS/LedgerTargetApp/`. Every Swift file is
listed once. These are current implementation classifications, not future plans.

| Files | Class | Boundary/disposition |
|---|---|---|
| DownloadedItemImagesView.swift; DownloadedImageZoomSurface.swift | C/B | Reused presentation seam should have been evaluated; keep protected loading. |
| DownloadedItemsView.swift | U/B/A | New Item list/detail presentation around necessary projections; compare original components before expansion. |
| DownloadedItemThumbnailView.swift | B/U | Authorized async image/viewport lifetime is needed; card integration should reuse original presentation where feasible. |
| SpaceChecklistEditorStagingExerciseView.swift | C/B | Existing editor callback is a concrete reuse seam; retain command/rejection model. |
| PropertyManagementReportPreview.swift; ClientSummaryPhysicalReportPreview.swift | B/U | New report data is justified; wholesale preview/layout replacement is not established as necessary. |
| PropertyManagementReportSystemDelivery.swift | B | Explicit native destination lifetime/security rationale; not wholesale waste. |
| LocalVendorPDFParser.swift | R/B | Wraps five original parser/helper sources. |
| LocalVendorPDFThumbnailExtractor.swift | B | Different conservative extraction/association algorithm, not merely a renamed old extractor. |
| LocalVendorDocumentReviewView.swift | B/U | Real local-review boundary; original review UI reuse remains an open technical choice. |
| AccountBusinessProfileView.swift | B/U | Read-only authorized branding surface, not complete settings replacement. |
| WorkspaceAccessGate.swift; AccountDiscoveryStagingExercise.swift; AccountPendingWorkStagingExerciseView.swift | B/H | Required access/durability behavior with diagnostic presentation. |
| AccountPendingWorkStagingRuntimeAdapter.swift | B | Thin forwarding boundary, not duplicate UI. |
| LedgerTargetStagingApp.swift; ActiveWorkspaceChecklistUITestFixture.swift | H/B | Isolated app bootstrap and synthetic harness, not production feature-completeness evidence. |
| ActiveWorkspaceToSpaceChecklistStagingComposition.swift | B/H/U | Scoped orchestration is useful; shell/cards/checklist presentation must not become default reconstruction. |
| SpaceBrowserStagingComposition.swift; SpaceCoreDetailsStagingExerciseView.swift; ReferencedSpaceDetailView.swift | B/H/U | Keep local routes/authorization; decide reuse of original Space presentation. |
| SpaceCoreDetailsStagingRuntimeAdapter.swift | B | Runtime forwarding plus checklist-toggle adapter. |
| ProjectSetupStagingExerciseView.swift | A/B/U | Redesigned Client/setup logic; wizard presentation reuse still requires disposition. |
| ProjectSetupStagingRuntimeAdapter.swift | B | Thin wiring. |
| ProjectBrowsingStagingExerciseView.swift; ClientBrowsingStagingExerciseView.swift; ProjectNoteHistoryStagingExerciseView.swift | A/B/H/U | New Client/read authority and diagnostic browsers; not justified final-screen reconstruction by themselves. |
| ProjectBrowsingStagingRuntimeAdapter.swift; ProjectArchiveBrowserStagingRuntimeAdapter.swift; ClientBrowsingStagingRuntimeAdapter.swift; ClientArchiveBrowserStagingRuntimeAdapter.swift | B | Scoped runtime forwarding; small wiring files are not evidence of a UI rewrite. |
| SpaceAssignmentDestinationStagingExerciseView.swift; TransferDestinationSelectionStagingExerciseView.swift | B/H | Small diagnostic pickers for scope/eligibility. |
| SpaceAssignmentDestinationStagingRuntimeAdapter.swift; TransferDestinationSelectionStagingRuntimeAdapter.swift | B | Thin forwarding. |
| ClientRenameStagingExercise.swift; ProjectCategoryConfigurationStagingExerciseView.swift; ProjectCategoryConfigurationStagingRuntimeAdapter.swift; SpaceCreationStagingExerciseView.swift; SpaceCreationStagingRuntimeAdapter.swift; VendorSuggestionPickerRuntimeAdapter.swift; VendorSuggestionPickerView.swift | N | Comment-only scaffolds, not implemented replacement features. |

## Other implemented families: preserve versus reconsider

Prefixes below identify current files within their named modules; responsibilities
are classified as a family. This is not a claim of complete shipped workflows.

| Module/family | Classification and disposition |
|---|---|
| Core Client*, Project* setup/archive/rename/details/notes/preferences/category/directory contracts | A/B: Client/accounting redesign plus typed local/command contracts. Reuse old presentation; do not route these back through Firebase services. Extra per-command abstraction cost not established as minimal. |
| Core Space*, ItemSpace* and TransferDestinationSelection | A/B: atomic/revision-aware commands and scoped destination evidence; renderer/editor duplication assessed separately. |
| Core Downloaded*, ProjectItem*, FrozenInvoiceContents, ReceiptLineReconstruction, TransactionTaxonomy/TypeChoice | A/B: canonical physical/accounting/media evidence and behavior, not an excuse to rebuild UI. Identical pure sorting/formatting kernels are consolidation candidates. |
| Core PropertyManagementReport*, ClientSummaryPhysicalReport | A/B: new snapshots/eligibility and export contracts; rendering choices assessed separately. |
| Core DomainPrimitives, OperationLifecycle, Account*, Attachment*, SessionEndingPolicy, RejectedOperationRecovery, TargetEnvironment, ContractCatalog/GeneratedContractCatalog | B: identity, accepted-write durability, schema contracts and environment isolation. Existing Firebase SDK behavior is not a substitute. Scope/minimality of each abstraction is unproved here. |
| Core SharedListQueryPresentation, TypedEditDraft, ScopedRouteResolution, OperationalHealth, PrivacySafeTelemetry, LedgerReleaseManifest and remaining reference-data contracts | B/U: plausible cross-cutting contracts; this audit does not prove every generic profile, declaration or extension point needed implementation now. No deletion recommendation without consumer-level evidence. |
| AppModel *StagingExercise, Downloaded*Model, AccountBusinessProfileModel, report models, WorkspaceAccessPresentation | B/H: actual state machines/watch cancellation/pending/rejection behavior; keep useful controllers and connect them to reused presentation. Large controller size alone is not proof of necessity or waste. |
| AppModel *ReportPDF, PropertyManagementReportShareItem | B/U: documented rendering and handoff rationale; preserve correctness and recover required visual presentation separately. |
| AppModel ItemCardThumbnailGenerator | B/C: preserve strong validation; consolidate duplicated image kernel. |
| AppModel LocalVendorDocument* | R/B: review data/draft boundary around reused parsers. |
| PowerSync *Store, *Query, *Reader, *Watch, Supabase*RPC, Ledger* runtime/database/keychain/schema/upload, workspace removal and LocalOperationIdentityGuard | B: actual replacement backend, local storage, auth boundaries and replay integration. Six comment-only placeholders excluded from implemented claims. Preserve; genericity/size not independently justified by this role classification. |
| PowerSync AttachmentLocalByteVault, AttachmentCapturePowerSyncStore, SupabaseAccountLogoDownload, ReportScratchStore, report deliveries | B: byte durability, authorized retrieval and safe destination lifetime. Item images already reuse the logo downloaded-byte path; no second Item cache was introduced. |
| MigrationCore all16files; LedgerLocalPaymentImport | A/B: source preservation, transformation, quarantine, accounting reconciliation and guarded import. Not ordinary UI reimplementation. Production migration remains unauthorized/unperformed. |
| Composition ValidatedTargetComposition; Core TargetEnvironment/ReleaseManifest; TestSupport DeterministicTargetTestSupport | B/H/U: isolation/test infrastructure, not replaced product UI. Necessary guardrail purpose does not certify all scaffolding minimal. |
| LedgerItemThumbnail command-line utility | B: publishes verified derivatives through the shared generator; follows thumbnail-kernel disposition above. |
| Target MCP implemented Client creation, Project creation/archive review, reports, contract support/server/stdio and generated contracts | A/B: replaces privileged Firebase-facing integration with target commands/reads. clientRename.ts, spaceCreation.ts and spaceReadTools.ts are comment-only, not completed tools. |
| All37current SQL migration files and powersync/sync-streams.yaml | A/B: executable target schema/handlers/authorization/replication, including one uncommitted linked-Purchase migration. Do not classify a new SQL equivalent of an old Firestore operation as avoidable UI duplication. |
| Native/model/provider/MCP/SQL tests; CI and scripts | B/H/U: security/accounting/durability evidence remains valuable. Gallery-specific repair effort follows the viewer decision. Structural staging-name checks and repeated scaffolding are not proof of value; do not keep a replacement solely because its tests exist. |

Comment-only files are excluded from implemented-feature claims even when a
tracker or filename suggests a capability exists. Architectural declarations and
test helpers likewise do not establish app integration or hosted readiness.
