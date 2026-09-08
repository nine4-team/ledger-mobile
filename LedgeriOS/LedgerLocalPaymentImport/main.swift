import Foundation
import LedgerTargetCore
import LedgerTargetMigrationCore
#if os(macOS)
import Darwin

// Deliberately local synthetic execution only. Integrity records describe the
// work; they are evidence, not permission to import production data.
struct ImportFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
struct TestInterruption: Error {}
func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw ImportFailure(message) }
}
func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}
func command(_ arguments: [String], input: String = "") throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let stdin = Pipe(), stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    // Keep diagnostics out of the data channel; no credentials are accepted.
    process.standardError = FileHandle.standardError
    try process.run()
    try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "Local command failed: \(arguments.first ?? "command")")
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func regularFile(_ path: String) throws -> Bool {
    var info = stat()
    if lstat(path, &info) != 0 {
        if errno == ENOENT { return false }
        throw ImportFailure("Cannot inspect run artifact")
    }
    try require((info.st_mode & S_IFMT) == S_IFREG && info.st_nlink == 1,
        "Run artifacts must be ordinary unlinked files")
    return true
}
func durableWrite(_ bytes: Data, to path: String, directory: String) throws {
    _ = try regularFile(path)
    let temporary = directory + "/.write-" + UUID().uuidString
    let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    try require(fd >= 0, "Cannot create durable artifact")
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close(); _ = unlink(temporary) }
    try handle.write(contentsOf: bytes)
    try handle.synchronize()
    try require(rename(temporary, path) == 0, "Cannot replace durable artifact")
    let parent = open(directory, O_RDONLY | O_CLOEXEC)
    try require(parent >= 0, "Cannot open artifact directory")
    defer { close(parent) }
    try require(fsync(parent) == 0, "Cannot synchronize artifact directory")
}
func retain(_ bytes: Data, at path: String, directory: String) throws {
    if try regularFile(path) {
        try require(try Data(contentsOf: URL(fileURLWithPath: path)) == bytes, "Changed persisted artifact: \(URL(fileURLWithPath: path).lastPathComponent)")
    } else {
        try durableWrite(bytes, to: path, directory: directory)
    }
}
func envelope(_ source: FirebaseSourceDocument) -> FirebaseSourceValue {
    .map([
        .init(key: "accountScopeID", value: .string(source.accountScopeID)),
        .init(key: "documentPathSegments", value: .reference(segments: source.documentPathSegments)),
        .init(key: "entityCode", value: .string(source.entityCode)),
        .init(key: "evidenceKind", value: .string(source.evidenceKind.rawValue)),
        .init(key: "fields", value: source.fields),
        .init(key: "sourceRecordID", value: .string(source.sourceRecordID))
    ])
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    try require(args.count == 2 || args.count == 3,
        "Usage: LedgerLocalPaymentImport --run-directory <existing absolute directory> [--interrupt-before-commit|--interrupt-after-commit]")
    try require(args[0] == "--run-directory" && args[1].hasPrefix("/"), "An absolute run directory is required")
    let interruption = args.count == 3 ? args[2] : ""
    try require(["", "--interrupt-before-commit", "--interrupt-after-commit"].contains(interruption), "Unknown interruption option")
    let directory = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath().standardizedFileURL.path
    var isDirectory: ObjCBool = false
    try require(FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) && isDirectory.boolValue,
        "Run directory must already exist")
    var directoryInfo = stat()
    try require(lstat(directory, &directoryInfo) == 0 && directoryInfo.st_uid == getuid()
        && (directoryInfo.st_mode & 0o077) == 0,
        "Run directory must be owned by this user and private (0700)")
    let root = URL(fileURLWithPath: try command(["git", "rev-parse", "--show-toplevel"])).resolvingSymlinksInPath().path
    try require(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path == root,
        "Run from the isolated Supabase repository root")
    try require(directory != root && directory != "/" && directory != FileManager.default.homeDirectoryForCurrentUser.path,
        "Use a dedicated temporary run directory")
    let lockPath = directory + "/.lock"
    _ = try regularFile(lockPath)
    let lock = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    try require(lock >= 0, "Cannot open run lock")
    defer { close(lock) }
    try require(flock(lock, LOCK_EX | LOCK_NB) == 0, "Run directory is already in use")

    let environment = ProcessInfo.processInfo.environment
    try require((environment["DOCKER_HOST"] ?? "").isEmpty && (environment["DOCKER_CONTEXT"] ?? "").isEmpty,
        "Docker host/context environment overrides are not permitted")
    let context = try command(["docker", "context", "show"])
    let endpoint = try command(["docker", "context", "inspect", context, "--format", "{{.Endpoints.docker.Host}}"])
    try require(endpoint.hasPrefix("unix:///"), "Only a local Docker Unix socket is permitted")
    let docker = ["docker", "--context", context]
    let container = "supabase_db_ledger_target_supabase_local"
    let labelsJSON = try command(docker + ["inspect", "--format", "{{json .Config.Labels}}", container])
    let labels = try JSONDecoder().decode([String: String].self, from: Data(labelsJSON.utf8))
    try require(labels["com.supabase.cli.project"] == "ledger_target_supabase_local", "Unexpected local Supabase project")
    guard let workdir = labels["com.supabase.cli.workdir"] else { throw ImportFailure("Missing local Supabase workdir") }
    try require(URL(fileURLWithPath: workdir).resolvingSymlinksInPath().path == root, "Local database belongs to another checkout")
    let sqlArguments = docker + ["exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1"]
    func sql(_ text: String) throws -> String {
        try command(sqlArguments, input: "set standard_conforming_strings=on; set statement_timeout='15s';\n" + text)
    }
    func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }

    let runHex = String(try MigrationSHA256.make(bytes: Data(directory.utf8)).rawValue.prefix(32))
    let runID = try MigrationOpaqueID(validating: runHex, field: "run")
    let sourceAccount = "synthetic-local-payment-import"
    let projectID = "local-payment-project-" + runHex
    let sourceProjectID = "source-project-" + runHex
    let project = FirebaseSourceDocument(accountScopeID: sourceAccount,
        documentPathSegments: ["accounts", sourceAccount, "projects", sourceProjectID], entityCode: "projects",
        evidenceKind: .record, fields: .map([
            .init(key: "clientName", value: .string("Synthetic Client")),
            .init(key: "notes", value: .string("  Original Project notes\nKeep the blue sofa.  "))
        ]), sourceRecordID: sourceProjectID)
    let sources: [FirebaseSourceDocument] = [23, 37].enumerated().map { offset, amount in
        let id = "local-payment-\(runHex)-\(offset + 1)"
        return FirebaseSourceDocument(accountScopeID: sourceAccount,
            documentPathSegments: ["accounts", sourceAccount, "transactions", id], entityCode: "transactions", evidenceKind: .record,
            fields: .map([
                .init(key: "amountCents", value: .integer(String(amount))),
                .init(key: "notes", value: .string("synthetic\0payment")),
                .init(key: "projectId", value: .string(sourceProjectID)),
                .init(key: "settlementInvoiceId", value: .string("synthetic-invoice")),
                .init(key: "settlementInvoiceLineIds", value: .array([.string("synthetic-line")])),
                .init(key: "type", value: .string("paymentToBusiness"))
            ]), sourceRecordID: id)
    }
    let scope = TransactionScope.project(accountId: try AccountID(validating: "account-primary"),
        projectId: try ProjectID(validating: projectID), clientId: try ClientID(validating: "client-existing"))
    let identities = try sources.map {
        FirebasePaymentIdentityMapping(sourcePath: $0.documentPathSegments, targetID: try TransactionID(validating: $0.sourceRecordID))
    }
    let assignments = [FirebasePaymentProjectMapping(sourceProject: project, targetScope: scope)]
    func batch() -> FirebasePaymentBatchResult {
        FirebaseClientPaymentBatch.convert(transactions: sources, projects: [project], sourceAccountID: sourceAccount,
            targetAccountID: scope.accountId, projectMappings: assignments, identityMappings: identities)
    }
    let converted = batch()
    try require(converted.isFullyReconciled && converted.mappedCount == 2 && converted.mappedTotalCents == 60,
        "Synthetic payment batch did not reconcile")
    let parameters = try FirebaseClientPaymentImportParameters.make(batch: converted, currency: CurrencyCode(validating: "USD"))
    func legacyNotesParameters() throws -> FirebaseProjectLegacyNotesImportParameters {
        try FirebaseProjectLegacyNotesImportParameters.make(FirebaseProjectLegacyNotesConversion.convert(project,
            sourceAccountID: sourceAccount, sourceProjectID: sourceProjectID,
            targetAccountID: scope.accountId, targetProjectID: ProjectID(validating: projectID)))
    }
    let noteParameters = try legacyNotesParameters()
    let sourceBytes = try FirebaseSourceFixtureCatalog.canonicalData(for: .array(([project] + sources).map(envelope)))
    var mappingRows = parameters.map {
        ["sourceAccount": $0.p_source_account, "sourceDocument": $0.p_source_document, "targetID": $0.p_id,
         "accountID": $0.p_account_id, "projectID": $0.p_project_id, "clientID": $0.p_client_id, "currency": $0.p_currency]
    }
    mappingRows.append(["sourceAccount": noteParameters.p_source_account,
        "sourceDocument": noteParameters.p_source_document, "targetID": noteParameters.p_project_id,
        "accountID": noteParameters.p_account_id, "entity": "project_legacy_notes"])
    let mappingBytes = try canonical(mappingRows)
    let binaryURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let binaryBytes = try Data(contentsOf: binaryURL)
    func artifact(_ code: String, _ bytes: Data) throws -> MigrationArtifactIdentity {
        try .init(id: MigrationStableCode(validating: code, field: "artifact"), version: MigrationVersion(validating: "1", field: "version"),
            byteCount: Int64(bytes.count), sha256: .make(bytes: bytes))
    }
    let contracts = LedgerContractVersions(schema: "1", query: "1", operation: "1", sync: "1")
    // These identifiers are derived from the inspected local endpoint/checkout.
    // No app environment receipt is repurposed as execution authority.
    let resources = LedgerTargetComponent.allCases.map {
        LedgerEnvironmentResource(component: $0, environment: .targetLocal,
            publicIdentifier: "local-payment:\(endpoint):\(container):\(root):\($0.rawValue)")
    }
    let bundle = "apps.nine4.ledger.localpaymentimport"
    let manifest = LedgerEnvironmentManifest(environment: .targetLocal, buildProfile: .targetLocalDevelopment,
        bundleIdentifier: bundle, displayName: "Ledger Local Payment Import", localDataNamespacePrefix: "ledger.localpayment",
        contractVersions: contracts, resources: resources)
    let validatedEnvironment = try LedgerEnvironmentValidator.validate(manifest, policy: LedgerEnvironmentPolicy(
        expectedEnvironment: .targetLocal, expectedBuildProfile: .targetLocalDevelopment, expectedBundleIdentifier: bundle,
        expectedContractVersions: contracts, allowedResourceIdentifiers: Dictionary(uniqueKeysWithValues: resources.map { ($0.component, Set([$0.publicIdentifier])) }),
        forbiddenResourceIdentifiers: [], forbiddenBundleIdentifiers: []))
    let target = try MigrationTargetBinding.make(validatedEnvironment: validatedEnvironment)
    let executableArtifact = try artifact("local_payment_executable", binaryBytes)
    let mappings = [try artifact("payment_scope_mapping", mappingBytes)]
    let entity = try MigrationStableCode(validating: "client_payments", field: "entity")
    let notesEntity = try MigrationStableCode(validating: "project_legacy_notes", field: "entity")
    let validator = MigrationRunPlanValidator(policy: .init(expectedTarget: target, expectedContractVersions: contracts,
        expectedMigrationArtifact: executableArtifact, expectedMappingArtifacts: mappings, allowedSourceEnvironments: [.sourceFixture], allowedModes: [.apply]))
    // Fixed timestamp belongs to the fixed synthetic source, not a production export.
    let epoch: Int64 = 1_788_000_000_000
    let plan = try validator.validate(.init(runID: runID, mode: .apply,
        source: .init(environment: .sourceFixture, exportID: runID, capturedAtEpochMilliseconds: epoch,
            byteCount: Int64(sourceBytes.count), sha256: .make(bytes: sourceBytes)),
        target: target, accountScopeSHA256: .make(bytes: Data("\(sourceAccount):account-primary".utf8)),
        repositoryRevision: MigrationSourceRevision(validating: command(["git", "rev-parse", "HEAD"])), contractVersions: contracts,
        migrationArtifact: executableArtifact, mappingArtifacts: mappings,
        entityPlans: [.init(entity: entity, plannedCount: 2, sourceSHA256: .make(bytes: sourceBytes),
            transformVersion: MigrationVersion(validating: "payment-v1", field: "transform")),
            .init(entity: notesEntity, plannedCount: 1, sourceSHA256: .make(bytes: sourceBytes),
                transformVersion: MigrationVersion(validating: "legacy-notes-v1", field: "transform"))], createdAtEpochMilliseconds: epoch))
    let journalValidator = MigrationRunJournalValidator(planValidator: validator)
    let journalPath = directory + "/journal.json"
    // Once journal evidence exists, missing immutable inputs are corruption.
    if try regularFile(journalPath) {
        for name in ["source.json", "mappings.json", "plan.json"] {
            try require(try regularFile(directory + "/" + name), "Missing persisted artifact: \(name)")
        }
    }
    try retain(sourceBytes, at: directory + "/source.json", directory: directory)
    try retain(mappingBytes, at: directory + "/mappings.json", directory: directory)
    try retain(validator.canonicalData(for: plan), at: directory + "/plan.json", directory: directory)
    var journal = try regularFile(journalPath)
        ? journalValidator.decodeAndValidate(Data(contentsOf: URL(fileURLWithPath: journalPath)), plan: plan)
        : journalValidator.start(plan: plan)
    try require(journal.events.last?.state != .failed && journal.events.last?.state != .blocked,
        "Terminal failed or blocked journal cannot resume")
    func event(_ stage: MigrationStage, _ state: MigrationJournalEventState, applied: Int64) throws {
        let timestamp = max(Int64(Date().timeIntervalSince1970 * 1000), journal.events.last?.occurredAtEpochMilliseconds ?? epoch)
        let outcome = try MigrationEntityOutcome(entity: entity, examined: 2, applied: applied, skipped: 0, blocked: 0, failed: 0)
        let noteOutcome = try MigrationEntityOutcome(entity: notesEntity, examined: 1,
            applied: applied == 2 ? 1 : 0, skipped: 0, blocked: 0, failed: 0)
        journal = try journalValidator.appending(.make(planDigest: plan.contentDigest, sequence: journal.events.count + 1,
            stage: stage, state: state, occurredAtEpochMilliseconds: timestamp, outcomes: [outcome, noteOutcome]), to: journal, plan: plan)
        try durableWrite(journalValidator.canonicalData(for: journal, plan: plan), to: journalPath, directory: directory)
    }
    func isComplete(_ stage: MigrationStage) -> Bool {
        journal.events.contains { $0.stage == stage && $0.state == .completed }
    }
    func begin(_ stage: MigrationStage) throws {
        if journal.events.last?.stage != stage || journal.events.last?.state == .interrupted {
            try event(stage, .started, applied: isComplete(.load) ? 2 : 0)
        }
    }
    // Immutable payment/source evidence can be reused within this process. A
    // resumed process always starts with no readback evidence.
    var committedReadbackVerified = false
    func readback() throws {
        if committedReadbackVerified { return }
        for p in parameters {
            let expected = [p.p_id, p.p_account_id, p.p_project_id, p.p_client_id, p.p_amount, p.p_currency,
                p.p_source_account, p.p_source_document, String(p.p_source_bytes.dropFirst(2)), "purchase", "standalone", "firebase_client_payment"]
            let raw = try sql("""
                select json_build_array(t.id,t.account_id,t.project_id,t.client_id,t.amount_minor_units::text,t.currency,
                  s.source_account_id,s.source_document_id,encode(s.source_bytes,'hex'),t.type,t.role,t.origin)
                from public.spike_transactions t join ledger_private.imported_transaction_sources s
                  on s.transaction_id=t.id and s.account_id=t.account_id where t.id=\(quote(p.p_id));
                """)
            try require(try JSONDecoder().decode([String].self, from: Data(raw.utf8)) == expected,
                "Committed payment/source readback mismatch")
        }
        try require(try sql("select count(*)::text || ':' || sum(amount_minor_units)::text from public.spike_transactions where project_id=\(quote(projectID));") == "2:60",
            "Committed batch reconciliation mismatch")
        let expectedNotes: [String?] = [noteParameters.p_project_id, noteParameters.p_account_id,
            noteParameters.p_notes, noteParameters.p_source_account, noteParameters.p_source_document,
            String(noteParameters.p_source_bytes.dropFirst(2)), noteParameters.p_notes]
        let noteReadback = try sql("""
            select json_build_array(p.id,p.account_id,p.legacy_notes,s.source_account_id,s.source_document_id,
              encode(s.source_bytes,'hex'),s.imported_notes)
            from public.spike_projects p join ledger_private.imported_project_legacy_note_sources s
              on s.project_id=p.id and s.account_id=p.account_id where p.id=\(quote(projectID));
            """)
        let actualNotes = try JSONDecoder().decode([String?].self, from: Data(noteReadback.utf8))
        try require(actualNotes.map { $0.map { Array($0.utf8) } }
            == expectedNotes.map { $0.map { Array($0.utf8) } },
            "Committed legacy-note/source readback mismatch")
        committedReadbackVerified = true
    }
    // Completed journals still require independent committed-state verification.
    if isComplete(.load) { try readback() }
    for stage in MigrationStage.allCases {
        if isComplete(stage) { continue }
        try begin(stage)
        switch stage {
        case .extract:
            try require(try Data(contentsOf: URL(fileURLWithPath: directory + "/source.json")) == sourceBytes, "Source changed")
        case .normalize:
            let decoded = try FirebaseSourceFixtureCatalog.decodeValue(sourceBytes)
            try require(try FirebaseSourceFixtureCatalog.canonicalData(for: decoded) == sourceBytes, "Noncanonical synthetic source")
        case .transform:
            let recomputed = batch()
            try require(recomputed.isFullyReconciled && recomputed.mappedTotalCents == 60, "Transform failed reconciliation")
            try require(try FirebaseClientPaymentImportParameters.make(batch: recomputed, currency: CurrencyCode(validating: "USD")) == parameters,
                "Transform changed parameters")
            try require(try legacyNotesParameters() == noteParameters, "Legacy-note transform changed parameters")
        case .plan:
            _ = try validator.decodeAndValidate(Data(contentsOf: URL(fileURLWithPath: directory + "/plan.json")))
        case .load:
            let calls = parameters.map { p in
                "select ledger_private.import_client_payment(" + [p.p_id, p.p_account_id, p.p_project_id, p.p_client_id,
                    p.p_amount, p.p_currency, p.p_source_account, p.p_source_document, p.p_source_bytes].map(quote).joined(separator: ",") + ");"
            }.joined(separator: "\n")
            let transaction = """
                begin;
                insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
                values (\(quote(projectID)),'account-primary','client-existing','Synthetic local payment import',now(),now(),1,1,'principal-owner') on conflict(id) do nothing;
                \(calls)
                select ledger_private.import_project_legacy_notes(
                  \(quote(noteParameters.p_account_id)),\(quote(noteParameters.p_project_id)),
                  \(noteParameters.p_notes.map(quote) ?? "NULL"),\(quote(noteParameters.p_source_account)),
                  \(quote(noteParameters.p_source_document)),\(quote(noteParameters.p_source_bytes)));
                """
            // EOF with an open transaction causes PostgreSQL to roll it back.
            _ = try sql(transaction + (interruption == "--interrupt-before-commit" ? "\n" : "\ncommit;\n"))
            if !interruption.isEmpty { throw TestInterruption() }
            try readback()
        case .verify, .reconcile, .finalize:
            try readback()
        }
        try event(stage, .completed, applied: stage == .load || isComplete(.load) ? 2 : 0)
    }
    print("local-payment-import: run=\(runHex) committed=2 amount_minor_units=60 legacy_notes=1 journal=finalize/completed")
}

do { try run() }
catch is TestInterruption {
    FileHandle.standardError.write(Data("local-payment-import: intentional interruption before journal acknowledgement\n".utf8))
    exit(86)
}
catch {
    FileHandle.standardError.write(Data("local-payment-import: \(error)\n".utf8))
    exit(1)
}
#else
fatalError("LedgerLocalPaymentImport requires macOS and the isolated local Docker database")
#endif
