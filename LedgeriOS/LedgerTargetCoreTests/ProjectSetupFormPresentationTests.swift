import Foundation
import Testing
@testable import LedgerTargetCore

@Suite("Project Setup Form Presentation Contracts")
struct ProjectSetupFormPresentationTests {
    @Test("Preparation preserves exact source order, eligibility, and independent readiness")
    func preparationPreservesRepresentedEvidence() throws {
        let clientRows = try [
            Self.client("client-archived", lifecycle: .archived),
            Self.client("client-b", name: "Same Name"),
            Self.client("client-a", name: "Same Name")
        ]
        let clients = try Self.clientSelection(
            rows: clientRows,
            visibleCount: 5,
            quality: .stale,
            complete: false,
            version: "clients-stale",
            asOf: Self.t1
        )
        let categories = try Self.categories(
            rows: [
                Self.category("category-system", name: "System", order: 30, isSystem: true),
                Self.category("category-active-b", name: "Active B", order: 20),
                Self.category(
                    "category-archived",
                    name: "Archived",
                    order: 10,
                    lifecycle: .archived
                ),
                Self.category("category-active-a", name: "Active A", order: 5)
            ],
            quality: .partial,
            complete: false,
            version: "categories-partial",
            asOf: Self.t2
        )

        let preparation = try ProjectSetupFormPresentation.prepare(
            clientSelectionSnapshot: clients,
            categoryReferenceSnapshot: categories
        )

        #expect(preparation.accountId == Self.accountId)
        #expect(preparation.existingClients.map(\.id.rawValue) == ["client-b", "client-a"])
        #expect(preparation.existingClients.map(\.displayName.rawValue) == ["Same Name", "Same Name"])
        #expect(preparation.configurableCategories.map(\.id.rawValue) == [
            "category-active-a", "category-active-b"
        ])
        #expect(preparation.clientSelectionSnapshot == clients)
        #expect(preparation.categoryReferenceSnapshot == categories)
        #expect(preparation.clientReadiness == .stale)
        #expect(preparation.categoryReadiness == .partial)
        #expect(!preparation.clientSelectionSnapshot.isCompleteForQuery)
        #expect(!preparation.categoryReferenceSnapshot.local.isCompleteForQuery)
        #expect(preparation.clientSelectionSnapshot.visibleRowCountBeforeFiltering == 5)
        #expect(preparation.categoryReferenceSnapshot.local.localDataVersion.rawValue == "categories-partial")

        let encoded = String(
            decoding: try OperationContractCodec.encode(preparation),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "selectedclient", "defaultclient", "defaultcategory", "authorized",
            "firebase", "firestore", "supabase", "powersync", "https://", "token"
        ] {
            #expect(!encoded.contains(forbidden))
        }
    }

    @Test("Existing and new Client choices are exact and represented collisions fail locally")
    func exactClientChoicesAndCollisionBoundary() throws {
        let active = try Self.client("client-active", name: "Same Name")
        let sibling = try Self.client("client-sibling", name: "Same Name")
        let preparation = try Self.preparation(clientRows: [active, sibling])
        let projectName = try ProjectDisplayName(validating: "Project Alpha")

        let existingInput = try preparation.clientSelectionSnapshot.selection(clientId: active.id)
        let existing = try preparation.selection(
            client: existingInput,
            projectDisplayName: projectName,
            rawDescription: nil,
            categoryAllocations: []
        )
        #expect(existing.clientSelection == .existing(active.id))
        #expect(try Self.command(existing, preparation: preparation).draft.clientSelection == .existing(active.id))

        let newInput = ProjectClientSelectionInput(
            newClientId: try ClientID(validating: "client-new-unrepresented"),
            displayName: try ClientDisplayName(validating: "New Client")
        )
        let newSelection = try preparation.selection(
            client: newInput,
            projectDisplayName: projectName,
            rawDescription: nil,
            categoryAllocations: []
        )
        #expect(newSelection.clientSelection == newInput)
        #expect(try Self.command(newSelection, preparation: preparation).draft.clientSelection == newInput)

        #expect(Self.formFailure {
            try preparation.selection(
                client: .existing(ClientID(validating: "client-unknown")),
                projectDisplayName: projectName,
                rawDescription: nil,
                categoryAllocations: []
            )
        } == .clientNotSelectable)
        #expect(Self.formFailure {
            try preparation.selection(
                client: ProjectClientSelectionInput(
                    newClientId: active.id,
                    displayName: ClientDisplayName(validating: "Replacement Name")
                ),
                projectDisplayName: projectName,
                rawDescription: nil,
                categoryAllocations: []
            )
        } == .newClientIdentityCollision)

        let otherAccountCategories = try Self.categories(account: "account-other")
        #expect(Self.formFailure {
            try ProjectSetupFormPresentation.prepare(
                clientSelectionSnapshot: preparation.clientSelectionSnapshot,
                categoryReferenceSnapshot: otherAccountCategories
            )
        } == .accountScopeMismatch)

        let reboundActive = try Self.client(
            "client-active",
            name: "Changed represented evidence",
            updatedAt: Self.t3
        )
        let rebound = try Self.preparation(clientRows: [reboundActive, sibling])
        #expect(Self.formFailure {
            try Self.command(existing, preparation: rebound)
        } == .selectionPreparationMismatch)

        let changedCategoryEvidence = try ProjectSetupFormPresentation.prepare(
            clientSelectionSnapshot: preparation.clientSelectionSnapshot,
            categoryReferenceSnapshot: Self.categories(version: "categories-changed")
        )
        #expect(Self.formFailure {
            try Self.command(existing, preparation: changedCategoryEvidence)
        } == .selectionPreparationMismatch)

        let reordered = try Self.preparation(clientRows: [sibling, active])
        let inserted = try Self.preparation(
            clientRows: [active, sibling, Self.client("client-inserted")]
        )
        let removed = try Self.preparation(clientRows: [active])
        for changedEvidence in [reordered, inserted, removed] {
            #expect(Self.formFailure {
                try Self.command(existing, preparation: changedEvidence)
            } == .selectionPreparationMismatch)
        }
    }

    @Test("Command derivation preserves zero categories, nullable Money, mixed currencies, and description normalization")
    func exactCommandDerivationAndDescriptionNormalization() throws {
        let preparation = try Self.preparation()
        let client = try preparation.clientSelectionSnapshot.selection(
            clientId: preparation.existingClients[0].id
        )
        let projectName = try ProjectDisplayName(validating: "  Exact Project Name  ")
        let usd = try CurrencyCode(validating: "USD")
        let eur = try CurrencyCode(validating: "EUR")
        let allocations = try [
            Self.allocation("category-c", amount: Money(minorUnits: 5_000_000_000, currency: eur)),
            Self.allocation("category-a", amount: nil),
            Self.allocation("category-b", amount: Money(minorUnits: 0, currency: usd))
        ]
        let first = try preparation.selection(
            client: client,
            projectDisplayName: projectName,
            rawDescription: "  Description text\n",
            categoryAllocations: allocations
        )
        let reordered = try preparation.selection(
            client: client,
            projectDisplayName: projectName,
            rawDescription: "Description text",
            categoryAllocations: allocations.reversed()
        )

        #expect(first == reordered)
        #expect(first.categoryAllocations.map(\.categoryId.rawValue) == [
            "category-a", "category-b", "category-c"
        ])
        #expect(first.categoryAllocations[0].allocation == nil)
        #expect(first.categoryAllocations[1].allocation == Money(minorUnits: 0, currency: usd))
        #expect(first.categoryAllocations[2].allocation == Money(minorUnits: 5_000_000_000, currency: eur))
        #expect(first.descriptionReplacement.value == "Description text")

        let command = try Self.command(first, preparation: preparation)
        #expect(command.draft.accountId == Self.accountId)
        #expect(command.draft.projectId.rawValue == "project-new")
        #expect(command.draft.actorPrincipalId.rawValue == "principal-actor")
        #expect(command.draft.operationContractVersion.rawValue == "project-create-v1")
        #expect(command.draft.displayName.rawValue == "  Exact Project Name  ")
        #expect(command.draft.description == "Description text")
        #expect(command.draft.categoryAllocations == first.categoryAllocations)
        #expect(command.envelope.operationId.rawValue == "operation-create-project")
        #expect(command.envelope.clientCreatedAt == Self.t4)

        let zeroCategories = try preparation.selection(
            client: client,
            projectDisplayName: projectName,
            rawDescription: nil,
            categoryAllocations: []
        )
        #expect(try Self.command(zeroCategories, preparation: preparation).draft.categoryAllocations.isEmpty)

        for raw in [nil, "", " \n\t "] as [String?] {
            let selection = try preparation.selection(
                client: client,
                projectDisplayName: projectName,
                rawDescription: raw,
                categoryAllocations: []
            )
            #expect(selection.descriptionReplacement.value == nil)
            #expect(try Self.command(selection, preparation: preparation).draft.description == nil)
        }
    }

    @Test("Selection validation rejects duplicate, negative, unknown, inactive, and system categories")
    func invalidCategoryIntentFailsBeforeCommand() throws {
        let preparation = try Self.preparation()
        let client = ProjectClientSelectionInput.existing(preparation.existingClients[0].id)
        let projectName = try ProjectDisplayName(validating: "Project")
        let valid = try Self.allocation("category-a", amount: nil)

        #expect(Self.formFailure {
            try preparation.selection(
                client: client,
                projectDisplayName: projectName,
                rawDescription: nil,
                categoryAllocations: [valid, valid]
            )
        } == .duplicateCategoryIdentity)
        #expect(Self.formFailure {
            try preparation.selection(
                client: client,
                projectDisplayName: projectName,
                rawDescription: nil,
                categoryAllocations: [Self.allocation("category-unknown", amount: nil)]
            )
        } == .categoryNotSelectable)
        for categoryId in ["category-archived", "category-system"] {
            #expect(Self.formFailure {
                try preparation.selection(
                    client: client,
                    projectDisplayName: projectName,
                    rawDescription: nil,
                    categoryAllocations: [Self.allocation(categoryId, amount: nil)]
                )
            } == .categoryNotSelectable)
        }
        #expect(Self.setupFailure {
            try NullableCategoryAllocation(
                categoryId: BudgetCategoryID(validating: "category-a"),
                allocation: Money(
                    minorUnits: -1,
                    currency: CurrencyCode(validating: "USD")
                )
            )
        } == .negativeCategoryAllocation)
    }

    @Test("Canonical restart binds every source and selection field and refuses tamper")
    func canonicalRestartAndTamperRefusal() throws {
        let preparation = try Self.preparation(
            clientQuality: .partial,
            categoryQuality: .stale
        )
        let selection = try preparation.selection(
            client: .existing(preparation.existingClients[0].id),
            projectDisplayName: ProjectDisplayName(validating: "Restart Project"),
            rawDescription: " Restart description ",
            categoryAllocations: [Self.allocation("category-a", amount: nil)]
        )
        let restart = RestartFixture(preparation: preparation, selection: selection)
        let bytes = try OperationContractCodec.encode(restart)
        let restored = try OperationContractCodec.decode(RestartFixture.self, from: bytes)
        #expect(restored == restart)
        #expect(try OperationContractCodec.encode(restored) == bytes)
        #expect(restored.preparation.clientReadiness == .partial)
        #expect(restored.preparation.categoryReadiness == .stale)
        #expect(try Self.command(restored.selection, preparation: restored.preparation).draft.description == "Restart description")

        let preparationBytes = try OperationContractCodec.encode(preparation)
        let preparationMutations: [PreparationMutation] = [
            .init("preparation Account", .accountScopeMismatch) {
                $0["accountId"] = "account-other"
            },
            .init("preparation evidence fingerprint", .preparationFingerprintMismatch) {
                $0["evidenceFingerprint"] = Self.hash("8")
            },
            .init("Client snapshot Account", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "accountId", "account-other")
            },
            .init("Client source fingerprint", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "sourceDirectoryFingerprint", Self.hash("3"))
            },
            .init("Client query fingerprint", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "queryFingerprint", Self.hash("4"))
            },
            .init("Client evidence fingerprint", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "evidenceFingerprint", Self.hash("9"))
            },
            .init("Client source row count", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "sourceDirectoryRowCount", 3)
                Self.setClientSnapshotField(&$0, "visibleRowCountBeforeFiltering", 3)
            },
            .init("Client visible count", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "visibleRowCountBeforeFiltering", 3)
            },
            .init("Client completeness", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "isCompleteForQuery", true)
                Self.setClientSnapshotField(&$0, "quality", "ready")
            },
            .init("Client quality", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "quality", "stale")
            },
            .init("Client local version", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "localDataVersion", "client-version-changed")
            },
            .init("Client as-of", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "asOf", Self.milliseconds(Self.t3))
            },
            .init("Client availability", .invalidEncodedPreparation) {
                Self.setClientSnapshotField(&$0, "availability", "directoryIncomplete")
            },
            .init("Client row ID", .invalidEncodedPreparation) {
                Self.setClientRowField(&$0, "id", "client-changed")
            },
            .init("Client row Account", .invalidEncodedPreparation) {
                Self.setClientRowField(&$0, "accountId", "account-other")
            },
            .init("Client row display name", .invalidEncodedPreparation) {
                Self.setClientRowField(&$0, "displayName", "Changed Client")
            },
            .init("Client row lifecycle", .invalidEncodedPreparation) {
                Self.setClientRowField(&$0, "lifecycle", "archived")
            },
            .init("Client row created-at", .invalidEncodedPreparation) {
                Self.setClientRowField(&$0, "createdAt", Self.milliseconds(Self.t0) + 1)
            },
            .init("Client row updated-at", .invalidEncodedPreparation) {
                Self.setClientRowField(&$0, "updatedAt", Self.milliseconds(Self.t3))
            },
            .init("category query fingerprint", .preparationFingerprintMismatch) {
                Self.setCategoryLocalField(&$0, "queryFingerprint", Self.hash("5"))
            },
            .init("category snapshot Account", .invalidEncodedPreparation) {
                Self.setCategoryReferenceField(&$0, "accountId", "account-other")
            },
            .init("category visible count", .invalidEncodedPreparation) {
                Self.setCategoryLocalField(&$0, "visibleRowCountBeforeFiltering", 6)
            },
            .init("category completeness", .preparationFingerprintMismatch) {
                Self.setCategoryLocalField(&$0, "isCompleteForQuery", true)
                Self.setCategoryLocalField(&$0, "quality", "ready")
            },
            .init("category quality", .preparationFingerprintMismatch) {
                Self.setCategoryLocalField(&$0, "quality", "partial")
            },
            .init("category local version", .preparationFingerprintMismatch) {
                Self.setCategoryLocalField(&$0, "localDataVersion", "category-version-changed")
            },
            .init("category as-of", .preparationFingerprintMismatch) {
                Self.setCategoryLocalField(&$0, "asOf", Self.milliseconds(Self.t3))
            },
            .init("category ID", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "id", "category-changed")
            },
            .init("category Account", .invalidEncodedPreparation) {
                Self.setCategoryRowField(&$0, "accountId", "account-other")
            },
            .init("category name", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "name", "Changed Category")
            },
            .init("category kind", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "kind", "itemized")
            },
            .init("category lifecycle", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "lifecycle", "archived")
            },
            .init("category system flag", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "isSystem", true)
            },
            .init("category overall exclusion", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "excludesFromOverallBudget", true)
            },
            .init("category presentation order", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "presentationOrder", 11)
            },
            .init("category revision", .preparationFingerprintMismatch) {
                Self.setCategoryRowField(&$0, "revision", 2)
            }
        ]
        for mutation in preparationMutations {
            let actual = Self.preparationDecodeFailure(
                try Self.mutate(preparationBytes, mutation.apply)
            )
            if actual != mutation.expected {
                Issue.record(
                    "\(mutation.name): expected \(mutation.expected), got \(String(describing: actual))"
                )
            }
        }

        let changedClientOrder = try Self.mutate(preparationBytes) { root in
            var source = root["clientSelectionSnapshot"] as! [String: Any]
            var clients = source["activeClients"] as! [[String: Any]]
            clients.swapAt(0, 1)
            source["activeClients"] = clients
            root["clientSelectionSnapshot"] = source
        }
        #expect(Self.preparationDecodeFailure(changedClientOrder) == .invalidEncodedPreparation)
        let changedCategory = try Self.mutate(preparationBytes) { root in
            var reference = root["categoryReferenceSnapshot"] as! [String: Any]
            var local = reference["local"] as! [String: Any]
            var categories = local["rows"] as! [[String: Any]]
            categories.removeLast()
            local["rows"] = categories
            local["visibleRowCountBeforeFiltering"] = categories.count
            reference["local"] = local
            root["categoryReferenceSnapshot"] = reference
        }
        #expect(Self.preparationDecodeFailure(changedCategory) == .preparationFingerprintMismatch)
        let reorderedCategories = try Self.mutate(preparationBytes) { root in
            var reference = root["categoryReferenceSnapshot"] as! [String: Any]
            var local = reference["local"] as! [String: Any]
            var categories = local["rows"] as! [[String: Any]]
            categories.swapAt(0, 1)
            local["rows"] = categories
            reference["local"] = local
            root["categoryReferenceSnapshot"] = reference
        }
        #expect(Self.preparationDecodeFailure(reorderedCategories) == .invalidEncodedPreparation)
        let insertedCategory = try Self.mutate(preparationBytes) { root in
            var reference = root["categoryReferenceSnapshot"] as! [String: Any]
            var local = reference["local"] as! [String: Any]
            var categories = local["rows"] as! [[String: Any]]
            var inserted = categories[0]
            inserted["id"] = "category-inserted"
            inserted["name"] = "Inserted Category"
            inserted["presentationOrder"] = 60
            categories.append(inserted)
            local["rows"] = categories
            local["visibleRowCountBeforeFiltering"] = categories.count
            reference["local"] = local
            root["categoryReferenceSnapshot"] = reference
        }
        #expect(Self.preparationDecodeFailure(insertedCategory) == .preparationFingerprintMismatch)
        let changedSourceVersion = try Self.mutate(preparationBytes) { root in
            var reference = root["categoryReferenceSnapshot"] as! [String: Any]
            var local = reference["local"] as! [String: Any]
            local["localDataVersion"] = "changed-version"
            reference["local"] = local
            root["categoryReferenceSnapshot"] = reference
        }
        #expect(Self.preparationDecodeFailure(changedSourceVersion) == .preparationFingerprintMismatch)
        let invalidPreparationFingerprint = try Self.mutate(preparationBytes) {
            $0["evidenceFingerprint"] = "not-a-hash"
        }
        #expect(Self.preparationDecodeFailure(invalidPreparationFingerprint) == .invalidPreparationFingerprint)
        let extraPreparationKey = try Self.mutate(preparationBytes) { $0["extra"] = true }
        #expect(Self.preparationDecodeFailure(extraPreparationKey) == .invalidEncodedPreparation)

        let selectionBytes = try OperationContractCodec.encode(selection)
        let changedClient = try Self.mutate(selectionBytes) { root in
            var client = root["clientSelection"] as! [String: Any]
            client["clientId"] = "client-b"
            root["clientSelection"] = client
        }
        #expect(Self.selectionDecodeFailure(changedClient) == .selectionFingerprintMismatch)
        let noncanonicalDescription = try Self.mutate(selectionBytes) { root in
            var replacement = root["descriptionReplacement"] as! [String: Any]
            replacement["value"] = " Restart description "
            root["descriptionReplacement"] = replacement
        }
        #expect(Self.selectionDecodeFailure(noncanonicalDescription) == .invalidEncodedSelection)
        let reorderedAllocationWire = try preparation.selection(
            client: selection.clientSelection,
            projectDisplayName: selection.projectDisplayName,
            rawDescription: selection.descriptionReplacement.value,
            categoryAllocations: [
                Self.allocation("category-b", amount: nil),
                Self.allocation("category-a", amount: nil)
            ]
        )
        #expect(reorderedAllocationWire.categoryAllocations.map(\.categoryId.rawValue) == [
            "category-a", "category-b"
        ])
        let invalidSelectionFingerprint = try Self.mutate(selectionBytes) {
            $0["selectionFingerprint"] = String(repeating: "A", count: 64)
        }
        #expect(Self.selectionDecodeFailure(invalidSelectionFingerprint) == .invalidSelectionFingerprint)
        let extraSelectionKey = try Self.mutate(selectionBytes) { $0["extra"] = true }
        #expect(Self.selectionDecodeFailure(extraSelectionKey) == .invalidEncodedSelection)
        let nestedSelectionKey = try Self.mutate(selectionBytes) { root in
            var client = root["clientSelection"] as! [String: Any]
            client["extra"] = true
            root["clientSelection"] = client
        }
        #expect(Self.selectionDecodeFailure(nestedSelectionKey) == .invalidEncodedSelection)
        let existingWithDisplayName = try Self.mutate(selectionBytes) { root in
            var client = root["clientSelection"] as! [String: Any]
            client["displayName"] = "Not allowed for existing"
            root["clientSelection"] = client
        }
        #expect(Self.selectionDecodeFailure(existingWithDisplayName) == .invalidEncodedSelection)

        let richSelection = try preparation.selection(
            client: ProjectClientSelectionInput(
                newClientId: ClientID(validating: "client-new-rich"),
                displayName: ClientDisplayName(validating: "Rich New Client")
            ),
            projectDisplayName: ProjectDisplayName(validating: "Rich Project"),
            rawDescription: "Rich description",
            categoryAllocations: [
                Self.allocation(
                    "category-a",
                    amount: Money(
                        minorUnits: 100,
                        currency: CurrencyCode(validating: "USD")
                    )
                ),
                Self.allocation(
                    "category-b",
                    amount: Money(
                        minorUnits: 200,
                        currency: CurrencyCode(validating: "EUR")
                    )
                )
            ]
        )
        let richSelectionBytes = try OperationContractCodec.encode(richSelection)
        let selectionMutations: [SelectionMutation] = [
            .init("selection Account", .selectionFingerprintMismatch) {
                $0["accountId"] = "account-other"
            },
            .init("Project name", .selectionFingerprintMismatch) {
                $0["projectDisplayName"] = "Changed Project"
            },
            .init("canonical description", .selectionFingerprintMismatch) {
                var replacement = $0["descriptionReplacement"] as! [String: Any]
                replacement["value"] = "Changed description"
                $0["descriptionReplacement"] = replacement
            },
            .init("Client ID", .selectionFingerprintMismatch) {
                Self.setSelectionClientField(&$0, "clientId", "client-new-changed")
            },
            .init("new Client display name", .selectionFingerprintMismatch) {
                Self.setSelectionClientField(&$0, "displayName", "Changed New Client")
            },
            .init("Client kind shape", .invalidEncodedSelection) {
                Self.setSelectionClientField(&$0, "kind", "existing")
            },
            .init("missing new Client display name", .invalidEncodedSelection) {
                Self.removeSelectionClientField(&$0, "displayName")
            },
            .init("allocation category", .selectionFingerprintMismatch) {
                Self.setSelectionAllocationField(
                    &$0,
                    index: 0,
                    field: "categoryId",
                    value: "category-c"
                )
            },
            .init("allocation amount", .selectionFingerprintMismatch) {
                Self.setSelectionMoneyField(
                    &$0,
                    index: 0,
                    field: "minorUnits",
                    value: 101
                )
            },
            .init("allocation currency", .selectionFingerprintMismatch) {
                Self.setSelectionMoneyField(
                    &$0,
                    index: 0,
                    field: "currency",
                    value: "CAD"
                )
            },
            .init("allocation order", .selectionFingerprintMismatch) {
                var allocations = $0["categoryAllocations"] as! [[String: Any]]
                allocations.swapAt(0, 1)
                $0["categoryAllocations"] = allocations
            },
            .init("preparation fingerprint", .selectionFingerprintMismatch) {
                $0["preparationEvidenceFingerprint"] = Self.hash("6")
            },
            .init("selection fingerprint", .selectionFingerprintMismatch) {
                $0["selectionFingerprint"] = Self.hash("7")
            },
            .init("invalid preparation fingerprint", .invalidPreparationFingerprint) {
                $0["preparationEvidenceFingerprint"] = "not-a-hash"
            }
        ]
        for mutation in selectionMutations {
            let actual = Self.selectionDecodeFailure(
                try Self.mutate(richSelectionBytes, mutation.apply)
            )
            if actual != mutation.expected {
                Issue.record(
                    "\(mutation.name): expected \(mutation.expected), got \(String(describing: actual))"
                )
            }
        }

        #expect(Self.setupFailure {
            try Self.command(
                selection,
                preparation: preparation,
                capturedAt: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        } == .invalidProjectCreatedAt)
    }

    @Test("Bounded failures are stable and the leaf has no operation or provider authority")
    func boundedDiagnosticsAndAuthorityExclusions() throws {
        let diagnostics: [(ProjectSetupFormFailure, String)] = [
            (.accountScopeMismatch, "project_setup_form_account_scope_mismatch"),
            (.clientNotSelectable, "project_setup_form_client_not_selectable"),
            (.newClientIdentityCollision, "project_setup_form_new_client_identity_collision"),
            (.categoryNotSelectable, "project_setup_form_category_not_selectable"),
            (.duplicateCategoryIdentity, "project_setup_form_category_identity_duplicate"),
            (.invalidPreparationFingerprint, "project_setup_form_preparation_fingerprint_invalid"),
            (.invalidSelectionFingerprint, "project_setup_form_selection_fingerprint_invalid"),
            (.preparationFingerprintMismatch, "project_setup_form_preparation_fingerprint_mismatch"),
            (.selectionFingerprintMismatch, "project_setup_form_selection_fingerprint_mismatch"),
            (.selectionPreparationMismatch, "project_setup_form_selection_preparation_mismatch"),
            (.invalidEncodedPreparation, "project_setup_form_preparation_encoding_invalid"),
            (.invalidEncodedSelection, "project_setup_form_selection_encoding_invalid")
        ]
        for (failure, expected) in diagnostics {
            #expect(failure.diagnosticCode == expected)
            #expect(expected.utf8.count <= 80)
            #expect(expected.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" })
        }

        let preparation = try Self.preparation()
        let selection = try preparation.selection(
            client: .existing(preparation.existingClients[0].id),
            projectDisplayName: ProjectDisplayName(validating: "Authority-Free Project"),
            rawDescription: nil,
            categoryAllocations: []
        )
        let text = String(
            decoding: try OperationContractCodec.encode(selection),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "principal", "authorization", "permission", "route", "port", "receipt",
            "provider", "firebase", "firestore", "supabase", "powersync", "schema",
            "rls", "sql", "persist", "migration", "hosted", "production", "result"
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_803_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_803_000_001)
    private static let t2 = Date(timeIntervalSince1970: 1_803_000_002)
    private static let t3 = Date(timeIntervalSince1970: 1_803_000_003)
    private static let t4 = Date(timeIntervalSince1970: 1_803_000_004)
    private static let accountId = try! AccountID(validating: "account-project-setup")

    private struct RestartFixture: Codable, Equatable, Sendable {
        let preparation: ProjectSetupFormPreparation
        let selection: ProjectSetupFormSelection
    }

    private struct PreparationMutation {
        let name: String
        let expected: ProjectSetupFormFailure
        let apply: (inout [String: Any]) -> Void

        init(
            _ name: String,
            _ expected: ProjectSetupFormFailure,
            apply: @escaping (inout [String: Any]) -> Void
        ) {
            self.name = name
            self.expected = expected
            self.apply = apply
        }
    }

    private struct SelectionMutation {
        let name: String
        let expected: ProjectSetupFormFailure
        let apply: (inout [String: Any]) -> Void

        init(
            _ name: String,
            _ expected: ProjectSetupFormFailure,
            apply: @escaping (inout [String: Any]) -> Void
        ) {
            self.name = name
            self.expected = expected
            self.apply = apply
        }
    }

    private static func client(
        _ id: String,
        account: String = "account-project-setup",
        name: String = "Client Name",
        lifecycle: DirectoryLifecycleState = .active,
        createdAt: Date = t0,
        updatedAt: Date = t1
    ) throws -> ClientSummary {
        try ClientSummary(
            id: ClientID(validating: id),
            accountId: AccountID(validating: account),
            displayName: ClientDisplayName(validating: name),
            lifecycle: lifecycle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func clientSelection(
        rows: [ClientSummary],
        account: String = "account-project-setup",
        visibleCount: Int? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "clients-ready",
        asOf: Date = t1
    ) throws -> ProjectExistingClientSelectionSnapshot {
        let local = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(
                validating: String(repeating: "1", count: 64)
            ),
            rows: rows,
            visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: asOf
        )
        return try ProjectExistingClientSelectionSnapshot(
            directory: ClientListSnapshot(
                accountId: AccountID(validating: account),
                local: local
            )
        )
    }

    private static func category(
        _ id: String,
        account: String = "account-project-setup",
        name: String,
        order: UInt32,
        lifecycle: DirectoryLifecycleState = .active,
        isSystem: Bool = false
    ) throws -> BudgetCategoryDefinitionSnapshot {
        BudgetCategoryDefinitionSnapshot(
            id: try BudgetCategoryID(validating: id),
            accountId: try AccountID(validating: account),
            name: try BudgetCategoryName(validating: name),
            kind: .general,
            lifecycle: lifecycle,
            isSystem: isSystem,
            excludesFromOverallBudget: false,
            presentationOrder: order,
            revision: 1
        )
    }

    private static func categories(
        account: String = "account-project-setup",
        rows: [BudgetCategoryDefinitionSnapshot]? = nil,
        quality: ListSnapshotQuality = .ready,
        complete: Bool = true,
        version: String = "categories-ready",
        asOf: Date = t2
    ) throws -> BudgetCategoryReferenceSnapshot {
        let resolvedRows = try rows ?? [
            category("category-c", account: account, name: "Category C", order: 30),
            category("category-a", account: account, name: "Category A", order: 10),
            category("category-system", account: account, name: "System", order: 40, isSystem: true),
            category(
                "category-archived",
                account: account,
                name: "Archived",
                order: 50,
                lifecycle: .archived
            ),
            category("category-b", account: account, name: "Category B", order: 20)
        ]
        let local = try ListLocalSnapshot(
            queryFingerprint: ListQueryFingerprint(
                validating: String(repeating: "2", count: 64)
            ),
            rows: resolvedRows,
            visibleRowCountBeforeFiltering: resolvedRows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: asOf
        )
        return try BudgetCategoryReferenceSnapshot(
            accountId: AccountID(validating: account),
            local: local
        )
    }

    private static func preparation(
        clientRows: [ClientSummary]? = nil,
        clientQuality: ListSnapshotQuality = .ready,
        categoryQuality: ListSnapshotQuality = .ready
    ) throws -> ProjectSetupFormPreparation {
        let clients = try clientRows ?? [client("client-a"), client("client-b")]
        return try ProjectSetupFormPresentation.prepare(
            clientSelectionSnapshot: clientSelection(
                rows: clients,
                quality: clientQuality,
                complete: clientQuality == .ready
            ),
            categoryReferenceSnapshot: categories(
                quality: categoryQuality,
                complete: categoryQuality == .ready
            )
        )
    }

    private static func allocation(
        _ categoryId: String,
        amount: Money?
    ) throws -> NullableCategoryAllocation {
        try NullableCategoryAllocation(
            categoryId: BudgetCategoryID(validating: categoryId),
            allocation: amount
        )
    }

    private static func command(
        _ selection: ProjectSetupFormSelection,
        preparation: ProjectSetupFormPreparation,
        capturedAt: Date = t4
    ) throws -> CreateProjectCommand {
        try selection.command(
            validating: preparation,
            projectId: ProjectID(validating: "project-new"),
            operationId: OperationID(validating: "operation-create-project"),
            actorPrincipalId: PrincipalID(validating: "principal-actor"),
            operationContractVersion: OperationContractVersion(
                validating: "project-create-v1"
            ),
            capturedAt: capturedAt
        )
    }

    private static func hash(_ character: Character) -> String {
        String(repeating: character, count: 64)
    }

    private static func milliseconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 * 1_000)
    }

    private static func setClientSnapshotField(
        _ root: inout [String: Any],
        _ field: String,
        _ value: Any
    ) {
        var snapshot = root["clientSelectionSnapshot"] as! [String: Any]
        snapshot[field] = value
        root["clientSelectionSnapshot"] = snapshot
    }

    private static func setClientRowField(
        _ root: inout [String: Any],
        _ field: String,
        _ value: Any
    ) {
        var snapshot = root["clientSelectionSnapshot"] as! [String: Any]
        var rows = snapshot["activeClients"] as! [[String: Any]]
        rows[0][field] = value
        snapshot["activeClients"] = rows
        root["clientSelectionSnapshot"] = snapshot
    }

    private static func setCategoryLocalField(
        _ root: inout [String: Any],
        _ field: String,
        _ value: Any
    ) {
        var reference = root["categoryReferenceSnapshot"] as! [String: Any]
        var local = reference["local"] as! [String: Any]
        local[field] = value
        reference["local"] = local
        root["categoryReferenceSnapshot"] = reference
    }

    private static func setCategoryReferenceField(
        _ root: inout [String: Any],
        _ field: String,
        _ value: Any
    ) {
        var reference = root["categoryReferenceSnapshot"] as! [String: Any]
        reference[field] = value
        root["categoryReferenceSnapshot"] = reference
    }

    private static func setCategoryRowField(
        _ root: inout [String: Any],
        _ field: String,
        _ value: Any
    ) {
        var reference = root["categoryReferenceSnapshot"] as! [String: Any]
        var local = reference["local"] as! [String: Any]
        var rows = local["rows"] as! [[String: Any]]
        rows[0][field] = value
        local["rows"] = rows
        reference["local"] = local
        root["categoryReferenceSnapshot"] = reference
    }

    private static func setSelectionClientField(
        _ root: inout [String: Any],
        _ field: String,
        _ value: Any
    ) {
        var client = root["clientSelection"] as! [String: Any]
        client[field] = value
        root["clientSelection"] = client
    }

    private static func removeSelectionClientField(
        _ root: inout [String: Any],
        _ field: String
    ) {
        var client = root["clientSelection"] as! [String: Any]
        client.removeValue(forKey: field)
        root["clientSelection"] = client
    }

    private static func setSelectionAllocationField(
        _ root: inout [String: Any],
        index: Int,
        field: String,
        value: Any
    ) {
        var allocations = root["categoryAllocations"] as! [[String: Any]]
        allocations[index][field] = value
        root["categoryAllocations"] = allocations
    }

    private static func setSelectionMoneyField(
        _ root: inout [String: Any],
        index: Int,
        field: String,
        value: Any
    ) {
        var allocations = root["categoryAllocations"] as! [[String: Any]]
        var money = allocations[index]["allocation"] as! [String: Any]
        money[field] = value
        allocations[index]["allocation"] = money
        root["categoryAllocations"] = allocations
    }

    private static func formFailure<Value>(
        _ body: () throws -> Value
    ) -> ProjectSetupFormFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectSetupFormFailure { return failure }
        catch { return nil }
    }

    private static func setupFailure<Value>(
        _ body: () throws -> Value
    ) -> ProjectSetupFailure? {
        do { _ = try body(); return nil }
        catch let failure as ProjectSetupFailure { return failure }
        catch { return nil }
    }

    private static func preparationDecodeFailure(_ bytes: Data) -> ProjectSetupFormFailure? {
        formFailure {
            try OperationContractCodec.decode(ProjectSetupFormPreparation.self, from: bytes)
        }
    }

    private static func selectionDecodeFailure(_ bytes: Data) -> ProjectSetupFormFailure? {
        formFailure {
            try OperationContractCodec.decode(ProjectSetupFormSelection.self, from: bytes)
        }
    }

    private static func mutate(
        _ bytes: Data,
        _ body: (inout [String: Any]) -> Void
    ) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        body(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
