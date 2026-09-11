import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetMigrationCore

@Suite("Migration Run Integrity")
struct MigrationRunIntegrityTests {
    @Test("A complete dry run produces canonical evidence and no authority")
    func completeDryRunIsCanonicalAndEvidenceOnly() throws {
        let fixture = try Self.fixture()
        let journal = try Self.completeJournal(fixture)
        let manifest = try fixture.manifestValidator.validate(
            fixture.manifestDraft(journal: journal)
        )

        #expect(fixture.plan.authorityDisposition == .evidenceOnly)
        #expect(journal.authorityDisposition == .evidenceOnly)
        #expect(manifest.authorityDisposition == .evidenceOnly)
        #expect(manifest.disposition == .completed)
        #expect(manifest.finalOutcomes.map(\.examined) == [3, 7])
        #expect(manifest.finalOutcomes.allSatisfy { $0.applied == 0 })
        #expect(fixture.plan.mappingArtifacts.map(\.id.rawValue) == ["account_mapping", "schema_mapping"])
        #expect(fixture.plan.entityPlans.map(\.entity.rawValue) == ["clients", "items"])

        let planBytes = try fixture.planValidator.canonicalData(for: fixture.plan)
        let journalBytes = try fixture.journalValidator.canonicalData(
            for: journal,
            plan: fixture.plan
        )
        let manifestBytes = try fixture.manifestValidator.canonicalData(for: manifest)
        #expect(try fixture.planValidator.decodeAndValidate(planBytes) == fixture.plan)
        #expect(
            try fixture.journalValidator.decodeAndValidate(
                journalBytes,
                plan: fixture.plan
            ) == journal
        )
        #expect(try fixture.manifestValidator.decodeAndValidate(manifestBytes) == manifest)

        let encoded = String(decoding: manifestBytes, as: UTF8.self)
        for forbidden in [
            "https://",
            "file://",
            "/Users/",
            "access_token",
            "service_role",
            "firebase",
            "supabase",
            "powersync",
            "account-private",
            "operator-private"
        ] {
            #expect(!encoded.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test("Interrupted journal evidence replays and resumes identically after restart")
    func interruptedJournalReplaysAndResumes() throws {
        let fixture = try Self.fixture()
        var journal = try fixture.journalValidator.start(plan: fixture.plan)
        let zero = try Self.outcomes(for: fixture.plan, examined: [0, 0])
        let started = try Self.event(
            fixture,
            sequence: 1,
            stage: .extract,
            state: .started,
            outcomes: zero
        )
        journal = try fixture.journalValidator.appending(
            started,
            to: journal,
            plan: fixture.plan
        )
        let interrupted = try Self.event(
            fixture,
            sequence: 2,
            stage: .extract,
            state: .interrupted,
            outcomes: zero
        )
        journal = try fixture.journalValidator.appending(
            interrupted,
            to: journal,
            plan: fixture.plan
        )

        let replay = try fixture.journalValidator.appending(
            interrupted,
            to: journal,
            plan: fixture.plan
        )
        #expect(replay == journal)

        let canonical = try fixture.journalValidator.canonicalData(
            for: journal,
            plan: fixture.plan
        )
        let restored = try fixture.journalValidator.decodeAndValidate(
            canonical,
            plan: fixture.plan
        )
        #expect(restored.resumeFingerprint == journal.resumeFingerprint)

        var resumed = restored
        resumed = try fixture.journalValidator.appending(
            Self.event(
                fixture,
                sequence: 3,
                stage: .extract,
                state: .started,
                outcomes: zero
            ),
            to: resumed,
            plan: fixture.plan
        )
        resumed = try fixture.journalValidator.appending(
            Self.event(
                fixture,
                sequence: 4,
                stage: .extract,
                state: .completed,
                outcomes: zero
            ),
            to: resumed,
            plan: fixture.plan
        )
        resumed = try Self.completeRemainingStages(
            fixture,
            journal: resumed,
            stages: Array(MigrationStage.allCases.dropFirst())
        )
        let manifest = try fixture.manifestValidator.validate(
            fixture.manifestDraft(journal: resumed)
        )
        #expect(manifest.disposition == .completed)
        #expect(resumed.events.map(\.sequence) == Array(1...resumed.events.count))
    }

    @Test("Wrong target, conflicting replay, regressions, and tamper fail closed")
    func invalidEvidenceFailsClosed() throws {
        let fixture = try Self.fixture()
        let otherTarget = try Self.fixture(targetKind: .targetProduction, targetSeed: "prod")
        #expect(Self.failure {
            try fixture.planValidator.validate(otherTarget.draft)
        } == .targetEnvironmentMismatch)

        var journal = try fixture.journalValidator.start(plan: fixture.plan)
        let zero = try Self.outcomes(for: fixture.plan, examined: [0, 0])
        let started = try Self.event(
            fixture,
            sequence: 1,
            stage: .extract,
            state: .started,
            outcomes: zero
        )
        journal = try fixture.journalValidator.appending(started, to: journal, plan: fixture.plan)
        let conflictingReplay = try MigrationJournalEvent.make(
            planDigest: fixture.plan.contentDigest,
            sequence: 1,
            stage: .extract,
            state: .started,
            occurredAtEpochMilliseconds: Self.eventEpoch + 999,
            outcomes: zero
        )
        #expect(Self.failure {
            try fixture.journalValidator.appending(
                conflictingReplay,
                to: journal,
                plan: fixture.plan
            )
        } == .eventReplayConflict(sequence: 1))

        let progressed = try Self.outcomes(for: fixture.plan, examined: [2, 2])
        let checkpoint = try Self.event(
            fixture,
            sequence: 2,
            stage: .extract,
            state: .checkpoint,
            outcomes: progressed
        )
        journal = try fixture.journalValidator.appending(checkpoint, to: journal, plan: fixture.plan)
        let regressed = try Self.event(
            fixture,
            sequence: 3,
            stage: .extract,
            state: .checkpoint,
            outcomes: try Self.outcomes(for: fixture.plan, examined: [1, 1])
        )
        #expect(Self.failure {
            try fixture.journalValidator.appending(regressed, to: journal, plan: fixture.plan)
        } == .eventCountRegression(sequence: 3, entity: fixture.plan.entityPlans[0].entity))

        let skippedStage = try Self.event(
            fixture,
            sequence: 3,
            stage: .transform,
            state: .started,
            outcomes: progressed
        )
        #expect(Self.failure {
            try fixture.journalValidator.appending(skippedStage, to: journal, plan: fixture.plan)
        } == .eventStageSkipped(sequence: 3))

        let planBytes = try fixture.planValidator.canonicalData(for: fixture.plan)
        var object = try #require(JSONSerialization.jsonObject(with: planBytes) as? [String: Any])
        object["contentDigest"] = String(repeating: "f", count: 64)
        let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(Self.failure {
            try fixture.planValidator.decodeAndValidate(tampered)
        } == .planDigestMismatch)

        object["mode"] = MigrationRunMode.apply.rawValue
        object["contentDigest"] = fixture.plan.contentDigest.rawValue
        let policyBypassAttempt = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        let unsafelyDecodedPlan = try JSONDecoder().decode(
            MigrationRunPlan.self,
            from: policyBypassAttempt
        )
        #expect(Self.failure {
            try fixture.journalValidator.start(plan: unsafelyDecodedPlan)
        } == .planDigestMismatch)

        #expect(Self.failure {
            try fixture.planValidator.decodeAndValidate(planBytes + Data([0x0a]))
        } == .noncanonicalPlan)
        #expect(Self.failure {
            try MigrationStableCode(validating: "https://private.invalid", field: "entity")
        } == .invalidStableCode("entity"))

        let oversized = Data(
            repeating: 0x20,
            count: MigrationRunPlanValidator.maximumCanonicalPlanBytes + 1
        )
        guard case .planTooLarge(let actual, let maximum) = Self.failure({
            try fixture.planValidator.decodeAndValidate(oversized)
        }) else {
            Issue.record("Oversized plan evidence should fail before decoding")
            return
        }
        #expect(actual == oversized.count)
        #expect(maximum == MigrationRunPlanValidator.maximumCanonicalPlanBytes)
    }

    @Test("Production-shaped apply evidence and blocked evidence remain non-executable")
    func productionAndBlockedEvidenceRemainNonExecutable() throws {
        let applyFixture = try Self.fixture(
            mode: .apply,
            targetKind: .targetProduction,
            targetSeed: "production"
        )
        let applyJournal = try Self.completeJournal(applyFixture)
        let applyManifest = try applyFixture.manifestValidator.validate(
            applyFixture.manifestDraft(journal: applyJournal)
        )
        #expect(applyManifest.authorityDisposition == .evidenceOnly)
        #expect(applyManifest.plan.target.environment == .targetProduction)
        #expect(applyManifest.finalOutcomes.map(\.applied) == [3, 7])

        let unexplained = try MigrationReconciliationResult(
            rule: applyFixture.rules[0],
            status: .unexplained,
            differenceCount: 1,
            evidenceSHA256: try .make(bytes: Data("unexplained".utf8))
        )
        let passedOther = try #require(
            applyFixture.reconciliation.first { $0.rule != applyFixture.rules[0] }
        )
        let incompleteResults = [unexplained, passedOther]
        #expect(Self.failure {
            try applyFixture.manifestValidator.validate(
                applyFixture.manifestDraft(
                    journal: applyJournal,
                    reconciliation: incompleteResults
                )
            )
        } == .unexplainedReconciliation(applyFixture.rules[0]))

        let notRun = try MigrationReconciliationResult(
            rule: applyFixture.rules[0],
            status: .notRun,
            differenceCount: 0,
            evidenceSHA256: try .make(bytes: Data("not-run".utf8))
        )
        #expect(Self.failure {
            try applyFixture.manifestValidator.validate(
                applyFixture.manifestDraft(
                    journal: applyJournal,
                    reconciliation: [notRun, passedOther]
                )
            )
        } == .incompleteReconciliation(applyFixture.rules[0]))

        let dryRunFixture = try Self.fixture()
        var blockedJournal = try dryRunFixture.journalValidator.start(plan: dryRunFixture.plan)
        let zero = try Self.outcomes(for: dryRunFixture.plan, examined: [0, 0])
        blockedJournal = try dryRunFixture.journalValidator.appending(
            Self.event(
                dryRunFixture,
                sequence: 1,
                stage: .extract,
                state: .started,
                outcomes: zero
            ),
            to: blockedJournal,
            plan: dryRunFixture.plan
        )
        let blockedOutcomes = [
            try MigrationEntityOutcome(
                entity: dryRunFixture.plan.entityPlans[0].entity,
                examined: 1,
                applied: 0,
                skipped: 0,
                blocked: 1,
                failed: 0
            ),
            try MigrationEntityOutcome(
                entity: dryRunFixture.plan.entityPlans[1].entity,
                examined: 0,
                applied: 0,
                skipped: 0,
                blocked: 0,
                failed: 0
            )
        ]
        blockedJournal = try dryRunFixture.journalValidator.appending(
            Self.event(
                dryRunFixture,
                sequence: 2,
                stage: .extract,
                state: .blocked,
                outcomes: blockedOutcomes
            ),
            to: blockedJournal,
            plan: dryRunFixture.plan
        )
        let blockedManifest = try dryRunFixture.manifestValidator.validate(
            dryRunFixture.manifestDraft(
                journal: blockedJournal,
                disposition: .blocked,
                reason: try MigrationStableCode(
                    validating: "ambiguous_source_record",
                    field: "reason"
                ),
                reconciliation: try dryRunFixture.rules.map { rule in
                    try MigrationReconciliationResult(
                        rule: rule,
                        status: .notRun,
                        differenceCount: 0,
                        evidenceSHA256: .make(bytes: Data("not-run-\(rule.rawValue)".utf8))
                    )
                }
            )
        )
        #expect(blockedManifest.disposition == .blocked)
        #expect(blockedManifest.authorityDisposition == .evidenceOnly)
        #expect(blockedManifest.finalOutcomes.reduce(0) { $0 + $1.blocked } == 1)
        #expect(blockedManifest.reconciliation.allSatisfy { $0.status == .notRun })
    }

    private static let contracts = LedgerContractVersions(
        schema: "1",
        query: "1",
        operation: "1",
        sync: "1"
    )
    private static let createdEpoch: Int64 = 1_788_000_000_000
    private static let eventEpoch: Int64 = createdEpoch + 1_000

    private struct Fixture {
        let draft: MigrationRunPlanDraft
        let plan: MigrationRunPlan
        let planValidator: MigrationRunPlanValidator
        let journalValidator: MigrationRunJournalValidator
        let manifestValidator: MigrationRunManifestValidator
        let rules: [MigrationStableCode]
        let reconciliation: [MigrationReconciliationResult]

        func manifestDraft(
            journal: MigrationRunJournal,
            disposition: MigrationRunDisposition = .completed,
            reason: MigrationStableCode? = nil,
            reconciliation: [MigrationReconciliationResult]? = nil
        ) -> MigrationRunManifestDraft {
            MigrationRunManifestDraft(
                plan: plan,
                journal: journal,
                endedAtEpochMilliseconds: MigrationRunIntegrityTests.eventEpoch + 10_000,
                disposition: disposition,
                reason: reason,
                reconciliation: reconciliation ?? self.reconciliation
            )
        }
    }

    private static func fixture(
        mode: MigrationRunMode = .dryRun,
        targetKind: LedgerEnvironmentKind = .targetStaging,
        targetSeed: String = "staging"
    ) throws -> Fixture {
        let target = try MigrationTargetBinding.make(
            validatedEnvironment: environment(kind: targetKind, seed: targetSeed)
        )
        let migrationArtifact = try artifact(
            id: "migration_bundle",
            version: "1.0.0",
            bytes: "migration-bundle-v1"
        )
        let mappings = [
            try artifact(id: "schema_mapping", version: "1", bytes: "schema-map-v1"),
            try artifact(id: "account_mapping", version: "1", bytes: "account-map-v1")
        ]
        let entityPlans = [
            try MigrationEntityPlan(
                entity: MigrationStableCode(validating: "items", field: "entity"),
                plannedCount: 7,
                sourceSHA256: .make(bytes: Data("items-source".utf8)),
                transformVersion: MigrationVersion(validating: "items-v1", field: "transform")
            ),
            try MigrationEntityPlan(
                entity: MigrationStableCode(validating: "clients", field: "entity"),
                plannedCount: 3,
                sourceSHA256: .make(bytes: Data("clients-source".utf8)),
                transformVersion: MigrationVersion(validating: "clients-v1", field: "transform")
            )
        ]
        let draft = MigrationRunPlanDraft(
            runID: try MigrationOpaqueID(
                validating: String(repeating: "1", count: 32),
                field: "run"
            ),
            mode: mode,
            source: try MigrationSourceSnapshot(
                environment: .sourceFixture,
                exportID: MigrationOpaqueID(
                    validating: String(repeating: "2", count: 32),
                    field: "export"
                ),
                capturedAtEpochMilliseconds: createdEpoch - 1_000,
                byteCount: 4_096,
                sha256: .make(bytes: Data("immutable-source-export".utf8))
            ),
            target: target,
            accountScopeSHA256: try .make(bytes: Data("opaque-account-scope".utf8)),
            repositoryRevision: try MigrationSourceRevision(
                validating: String(repeating: "a", count: 40)
            ),
            contractVersions: contracts,
            migrationArtifact: migrationArtifact,
            mappingArtifacts: mappings.reversed(),
            entityPlans: entityPlans,
            createdAtEpochMilliseconds: createdEpoch
        )
        let planValidator = MigrationRunPlanValidator(
            policy: MigrationRunPlanPolicy(
                expectedTarget: target,
                expectedContractVersions: contracts,
                expectedMigrationArtifact: migrationArtifact,
                expectedMappingArtifacts: mappings,
                allowedSourceEnvironments: [.sourceFixture],
                allowedModes: [.dryRun, .apply]
            )
        )
        let plan = try planValidator.validate(draft)
        let rules = [
            try MigrationStableCode(validating: "entity_coverage", field: "rule"),
            try MigrationStableCode(validating: "financial_invariants", field: "rule")
        ]
        let reconciliation = try rules.reversed().map { rule in
            try MigrationReconciliationResult(
                rule: rule,
                status: .passed,
                differenceCount: 0,
                evidenceSHA256: .make(bytes: Data("evidence-\(rule.rawValue)".utf8))
            )
        }
        let manifestValidator = MigrationRunManifestValidator(
            planValidator: planValidator,
            policy: MigrationRunManifestPolicy(requiredReconciliationRules: Set(rules))
        )
        return Fixture(
            draft: draft,
            plan: plan,
            planValidator: planValidator,
            journalValidator: MigrationRunJournalValidator(planValidator: planValidator),
            manifestValidator: manifestValidator,
            rules: rules,
            reconciliation: reconciliation
        )
    }

    private static func environment(
        kind: LedgerEnvironmentKind,
        seed: String
    ) throws -> ValidatedLedgerEnvironment {
        let profile: LedgerBuildProfile
        switch kind {
        case .targetLocal: profile = .targetLocalDevelopment
        case .targetStaging: profile = .targetStaging
        case .targetProduction: profile = .targetProductionArchive
        }
        let bundle = "apps.nine4.ledger.\(seed)"
        let resources = LedgerTargetComponent.allCases.map { component in
            LedgerEnvironmentResource(
                component: component,
                environment: kind,
                publicIdentifier: "\(seed)-\(component.rawValue.lowercased())"
            )
        }
        let manifest = LedgerEnvironmentManifest(
            environment: kind,
            buildProfile: profile,
            bundleIdentifier: bundle,
            displayName: kind == .targetStaging ? "Ledger STAGING" : "Ledger Target",
            localDataNamespacePrefix: "ledger.\(seed)",
            contractVersions: contracts,
            resources: resources
        )
        return try LedgerEnvironmentValidator.validate(
            manifest,
            policy: LedgerEnvironmentPolicy(
                expectedEnvironment: kind,
                expectedBuildProfile: profile,
                expectedBundleIdentifier: bundle,
                expectedContractVersions: contracts,
                allowedResourceIdentifiers: Dictionary(
                    uniqueKeysWithValues: resources.map {
                        ($0.component, Set([$0.publicIdentifier]))
                    }
                ),
                forbiddenResourceIdentifiers: [],
                forbiddenBundleIdentifiers: []
            )
        )
    }

    private static func artifact(
        id: String,
        version: String,
        bytes: String
    ) throws -> MigrationArtifactIdentity {
        let data = Data(bytes.utf8)
        return try MigrationArtifactIdentity(
            id: MigrationStableCode(validating: id, field: "artifact"),
            version: MigrationVersion(validating: version, field: "artifact"),
            byteCount: Int64(data.count),
            sha256: .make(bytes: data)
        )
    }

    private static func outcomes(
        for plan: MigrationRunPlan,
        examined: [Int64],
        applied: [Int64]? = nil
    ) throws -> [MigrationEntityOutcome] {
        try zip(plan.entityPlans, examined).enumerated().map { index, pair in
            try MigrationEntityOutcome(
                entity: pair.0.entity,
                examined: pair.1,
                applied: applied?[index] ?? 0,
                skipped: 0,
                blocked: 0,
                failed: 0
            )
        }
    }

    private static func finalOutcomes(for plan: MigrationRunPlan) throws -> [MigrationEntityOutcome] {
        let counts = plan.entityPlans.map(\.plannedCount)
        return try outcomes(
            for: plan,
            examined: counts,
            applied: plan.mode == .apply ? counts : nil
        )
    }

    private static func event(
        _ fixture: Fixture,
        sequence: Int,
        stage: MigrationStage,
        state: MigrationJournalEventState,
        outcomes: [MigrationEntityOutcome]
    ) throws -> MigrationJournalEvent {
        try MigrationJournalEvent.make(
            planDigest: fixture.plan.contentDigest,
            sequence: sequence,
            stage: stage,
            state: state,
            occurredAtEpochMilliseconds: eventEpoch + Int64(sequence),
            outcomes: outcomes
        )
    }

    private static func completeJournal(_ fixture: Fixture) throws -> MigrationRunJournal {
        try completeRemainingStages(
            fixture,
            journal: fixture.journalValidator.start(plan: fixture.plan),
            stages: MigrationStage.allCases
        )
    }

    private static func completeRemainingStages(
        _ fixture: Fixture,
        journal initial: MigrationRunJournal,
        stages: [MigrationStage]
    ) throws -> MigrationRunJournal {
        var journal = initial
        var current: [MigrationEntityOutcome]
        if let priorOutcomes = journal.events.last?.outcomes {
            current = priorOutcomes
        } else {
            current = try outcomes(
                for: fixture.plan,
                examined: fixture.plan.entityPlans.map { _ in 0 }
            )
        }
        for stage in stages {
            var sequence = journal.events.count + 1
            journal = try fixture.journalValidator.appending(
                event(
                    fixture,
                    sequence: sequence,
                    stage: stage,
                    state: .started,
                    outcomes: current
                ),
                to: journal,
                plan: fixture.plan
            )
            sequence += 1
            if stage == .finalize {
                current = try finalOutcomes(for: fixture.plan)
            }
            journal = try fixture.journalValidator.appending(
                event(
                    fixture,
                    sequence: sequence,
                    stage: stage,
                    state: .completed,
                    outcomes: current
                ),
                to: journal,
                plan: fixture.plan
            )
        }
        return journal
    }

    private static func failure<T>(_ operation: () throws -> T) -> MigrationIntegrityFailure? {
        do {
            _ = try operation()
            return nil
        } catch let failure as MigrationIntegrityFailure {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }
}
