import Foundation
import LedgerTargetCore
import Testing
@testable import LedgerTargetAppModel

@Suite("Project Browsing Staging Application Flow")
@MainActor
struct ProjectBrowsingStagingExerciseTests {
    @Test("One emission atomically preserves segment order, identity, and Project lifecycle")
    func atomicDirectoryProjection() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let details = DetailWatchProbe()
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))

        let rows = try [
            Self.project("archived-z", name: "Same", lifecycle: .archived),
            Self.project(
                "active-b",
                name: "Same",
                client: "client-b",
                clientName: "Archived Client",
                clientLifecycle: .archived
            ),
            Self.project("active-a", name: "Same", client: "client-a"),
            Self.project("archived-a", name: "Archived", lifecycle: .archived)
        ]
        directory.yield(try Self.directory(rows, visibleCount: 6))
        await Self.waitUntil { model.directoryPresentation != nil }

        let presentation = try #require(model.directoryPresentation)
        #expect(model.activeProjects.map(\.projectId) == [rows[1].id, rows[2].id])
        #expect(model.archivedProjects.map(\.projectId) == [rows[0].id, rows[3].id])
        #expect(model.activeProjects.map(\.projectDisplayName.rawValue) == ["Same", "Same"])
        #expect(model.activeProjects[0].clientLifecycle == .archived)
        #expect(presentation.active.localDataVersion == presentation.archived.localDataVersion)
        #expect(presentation.active.evidenceFingerprint != presentation.archived.evidenceFingerprint)
        #expect(!presentation.isSourceExhaustive)
        #expect(model.directoryStatus == "ready • complete • source nonexhaustive")
        #expect(model.directoryDiagnostic == nil)
        await model.stop()
    }

    @Test("Represented readiness never invents empty authority")
    func honestDirectoryReadinessAndEmptyMeaning() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory))
        #expect(model.activeProjects.isEmpty)
        #expect(model.directoryPresentation == nil)
        #expect(model.directoryStatus == "loading • completeness unknown")
        #expect(model.activeProjectCountLabel == "unknown")
        #expect(model.archivedProjectCountLabel == "unknown")

        let archived = try Self.project("archived", lifecycle: .archived)
        let cases: [(ListSnapshotQuality, Bool, Int, String, Bool)] = [
            (.partial, false, 1, "partial • incomplete • source exhaustive", false),
            (.stale, false, 1, "stale • incomplete • source exhaustive", false),
            (.ready, false, 2, "ready • incomplete • source nonexhaustive", false),
            (.ready, true, 2, "ready • complete • source nonexhaustive", false),
            (.ready, true, 1, "ready • complete • source exhaustive", true)
        ]
        for (index, item) in cases.enumerated() {
            directory.yield(try Self.directory(
                [archived],
                visibleCount: item.2,
                complete: item.1,
                quality: item.0,
                version: "directory-\(index)"
            ))
            await Self.waitUntil { model.directoryStatus == item.3 }
            let presentation = try #require(model.directoryPresentation)
            #expect(presentation.active.rows.isEmpty)
            #expect(presentation.active.isAuthoritativeEmpty == item.4)
            #expect(!presentation.archived.isAuthoritativeEmpty)
            #expect(model.activeProjectCountLabel == "0")
            #expect(model.archivedProjectCountLabel == "1")
        }

        let active = try Self.project("active")
        for (index, item) in cases.enumerated() {
            directory.yield(try Self.directory(
                [active],
                visibleCount: item.2,
                complete: item.1,
                quality: item.0,
                version: "mirrored-directory-\(index)"
            ))
            await Self.waitUntil {
                model.directoryPresentation?.active.localDataVersion.rawValue
                    == "mirrored-directory-\(index)"
            }
            let presentation = try #require(model.directoryPresentation)
            #expect(presentation.archived.rows.isEmpty)
            #expect(presentation.archived.isAuthoritativeEmpty == item.4)
            #expect(!presentation.active.isAuthoritativeEmpty)
            #expect(model.activeProjectCountLabel == "1")
            #expect(model.archivedProjectCountLabel == "0")
        }

        directory.finish(throwing: SourceFailure.upstream)
        await Self.waitUntil { model.directoryPresentation == nil }
        #expect(model.activeProjectCountLabel == "unknown")
        #expect(model.archivedProjectCountLabel == "unknown")
        await model.stop()
    }

    @Test(arguments: DirectoryTerminationCase.allCases)
    func directoryTerminationFailsClosed(_ terminal: DirectoryTerminationCase) async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        if terminal.isBeforeFirstValue { terminal.finish(directory) }
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory))

        if !terminal.isBeforeFirstValue {
            directory.yield(try Self.directory([Self.project("project-a")]))
            await Self.waitUntil { model.activeProjects.count == 1 }
            terminal.finish(directory)
        }

        await Self.waitUntil { model.directoryDiagnostic == terminal.diagnostic }
        #expect(model.activeProjects.isEmpty)
        #expect(model.archivedProjects.isEmpty)
        #expect(model.directoryPresentation == nil)
        #expect(model.directoryStatus == "blocked • completeness unknown")
        await Self.waitUntil { directory.terminationCount == 1 }
        #expect(directory.terminationCount == 1)
        await model.stop()
        #expect(directory.terminationCount == 1)
    }

    @Test("Cross-Account evidence fails closed and terminates its source exactly once")
    func crossAccountDirectoryFailsClosed() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory))
        directory.yield(try Self.directory([Self.project("project-a")]))
        await Self.waitUntil { model.activeProjects.count == 1 }

        directory.yield(try Self.directory(
            [Self.project("other-project", account: "other-account")],
            account: "other-account",
            version: "cross-account"
        ))
        await Self.waitUntil {
            model.directoryDiagnostic == "project_directory_evidence_invalid"
        }
        #expect(model.activeProjects.isEmpty)
        #expect(model.directoryPresentation == nil)
        await Self.waitUntil { directory.terminationCount == 1 }
        #expect(directory.terminationCount == 1)
        await model.stop()
    }

    @Test("Directory termination joins an active detail source before lifecycle drainage completes")
    func directoryTerminationDrainsActiveDetail() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let delayedDetail = DelayedCancellationDetailSource()
        let requests = DetailRequestRecorder()
        let runtime = ProjectBrowsingStagingRuntime(
            watchProjects: { directory.stream },
            watchProject: { request in
                requests.record(request)
                return delayedDetail.stream
            }
        )
        let model = Self.model()
        await model.start(runtime: runtime)
        let project = try Self.project("project-a")
        directory.yield(try Self.directory([project]))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: project.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(await Self.waitUntilAsync { await delayedDetail.isWaiting })

        directory.finish()
        await Self.waitUntil {
            model.directoryDiagnostic == "project_directory_source_completed"
        }
        #expect(model.selectedProject == nil)
        #expect(model.detailPresentation == nil)
        #expect(directory.terminationCount == 1)
        #expect(delayedDetail.terminationCount == 0)

        let completion = CompletionProbe()
        let stop = Task { @MainActor in
            completion.markStarted()
            await model.stop()
            completion.markFinished()
        }
        await Self.waitUntil { completion.didStart }
        for _ in 0..<20 { await Task.yield() }
        #expect(!completion.didFinish)
        #expect(delayedDetail.terminationCount == 0)

        await delayedDetail.releaseCancellation()
        await stop.value
        #expect(completion.didFinish)
        #expect(directory.terminationCount == 1)
        #expect(delayedDetail.terminationCount == 1)
        #expect(model.selectedProject == nil)
        #expect(model.detailPresentation == nil)
    }

    @Test("Selection is stable-ID and current-evidence bound")
    func exactSelectionAndRequestDispatch() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let detail = ControlledStream<ProjectCoreDetailsUpdate>()
        let details = DetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))

        await model.select(projectId: try ProjectID(validating: "missing"), segment: .active)
        #expect(model.detailDiagnostic == "project_detail_selection_invalid")
        #expect(details.requests.isEmpty)

        let active = try Self.project("active", name: "Same")
        let archived = try Self.project("archived", name: "Same", lifecycle: .archived)
        directory.yield(try Self.directory([active, archived]))
        await Self.waitUntil { model.directoryPresentation != nil }

        await model.select(projectId: archived.id, segment: .active)
        #expect(details.requests.isEmpty)
        #expect(model.detailDiagnostic == "project_detail_selection_invalid")

        await model.select(projectId: active.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }
        let request = try #require(details.requests.first)
        #expect(request.accountId == Self.accountId)
        #expect(request.projectId == active.id)
        #expect(model.selectedProjectId == active.id)
        #expect(model.selectedClientId == active.clientId)
        #expect(model.selectedProjectName == "Same")
        #expect(model.detailStateLabel == "awaiting local evidence")

        directory.yield(try Self.directory(
            [try Self.project("active", name: "Renamed"), archived],
            version: "refreshed"
        ))
        await Self.waitUntil { model.activeProjects.first?.projectDisplayName.rawValue == "Renamed" }
        #expect(details.requests.count == 1)
        #expect(model.selectedProjectName == "Same")

        await model.select(projectId: active.id, segment: .active)
        await Self.waitUntil { details.requests.count == 2 }
        #expect(model.selectedProjectName == "Renamed")
        await model.stop()
    }

    @Test("A selection captured before drainage cannot dispatch against refreshed evidence")
    func capturedSelectionRejectedAfterRefresh() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let delayedA = DelayedCancellationDetailSource()
        let detailB = ControlledStream<ProjectCoreDetailsUpdate>()
        let requests = DetailRequestRecorder()
        let projectA = try Self.project("project-a", name: "Project A", client: "client-a")
        let projectB = try Self.project("project-b", name: "Project B", client: "client-b")
        let runtime = ProjectBrowsingStagingRuntime(
            watchProjects: { directory.stream },
            watchProject: { request in
                requests.record(request)
                return request.projectId == projectA.id ? delayedA.stream : detailB.stream
            }
        )
        let model = Self.model()
        await model.start(runtime: runtime)
        directory.yield(try Self.directory([projectA, projectB]))
        await Self.waitUntil { model.activeProjects.count == 2 }
        await model.select(projectId: projectA.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        let isAwaitingA = await Self.waitUntilAsync { await delayedA.isWaiting }
        #expect(isAwaitingA)

        let selectB = Task { @MainActor in
            await model.select(projectId: projectB.id, segment: .active)
        }
        let renamedB = try Self.project(
            "project-b",
            name: "Project B Renamed",
            client: "client-b"
        )
        directory.yield(try Self.directory([projectA, renamedB], version: "selection-refresh"))
        await Self.waitUntil { model.activeProjects.last?.projectDisplayName.rawValue == "Project B Renamed" }
        await delayedA.releaseCancellation()
        await selectB.value

        #expect(requests.requests.count == 1)
        #expect(model.detailDiagnostic == "project_detail_selection_invalid")
        #expect(model.selectedProject == nil)

        await model.select(projectId: projectB.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 2 }
        #expect(model.selectedProjectName == "Project B Renamed")
        await model.stop()
    }

    @Test("Every detail presentation state remains exact across reactive updates")
    func completeDetailStateMatrix() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let detail = ControlledStream<ProjectCoreDetailsUpdate>()
        let details = DetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))
        let project = try Self.project("project-a")
        directory.yield(try Self.directory([project]))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: project.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }
        let request = try #require(details.requests.first)

        let renamedProject = try Self.project(
            "project-a",
            name: "Project Updated",
            clientName: "Client Updated"
        )
        detail.yield(try Self.snapshotUpdate(
            request,
            project: renamedProject,
            quality: .ready,
            complete: true,
            version: "newer-names"
        ))
        await Self.waitUntil { model.selectedProjectName == "Project Updated" }
        #expect(model.selectedClientName == "Client Updated")

        let cachedReady = try Self.detailLocal(
            request: request,
            rows: [Self.detailRow(project: renamedProject)],
            version: "cached-ready"
        )
        let cachedPartial = try Self.detailLocal(
            request: request,
            rows: [Self.detailRow(project: renamedProject)],
            complete: false,
            quality: .partial,
            version: "cached-partial"
        )
        let updates = try [
            Self.update(request, .waiting(.notRequested)),
            Self.update(request, .waiting(.loading)),
            Self.update(request, .waiting(.blocked)),
            Self.snapshotUpdate(request, project: project, quality: .ready, complete: true, version: "found-ready"),
            Self.snapshotUpdate(request, project: project, quality: .partial, complete: false, version: "found-partial"),
            Self.snapshotUpdate(request, project: project, quality: .stale, complete: false, version: "found-stale"),
            Self.emptyUpdate(request, quality: .ready, complete: false, version: "incomplete-ready"),
            Self.emptyUpdate(request, quality: .partial, complete: false, version: "incomplete-partial"),
            Self.emptyUpdate(request, quality: .stale, complete: false, version: "incomplete-stale"),
            Self.emptyUpdate(request, quality: .ready, complete: true, version: "absent"),
            Self.update(request, .failed(failure: .unavailable, cached: nil)),
            Self.update(request, .failed(failure: .retryable, cached: cachedReady)),
            Self.update(request, .failed(failure: .retryable, cached: nil)),
            Self.update(request, .failed(failure: .requiredUpdate, cached: cachedPartial)),
            Self.update(request, .failed(failure: .requiredUpdate, cached: nil))
        ]
        let labels = [
            "waiting", "waiting", "waiting",
            "found", "found", "found",
            "incomplete", "incomplete", "incomplete",
            "authoritative absence", "unavailable",
            "retryable • cached", "retryable • uncached",
            "required update • cached", "required update • uncached"
        ]
        let readiness = [
            "notRequested", "loading", "blocked",
            "ready", "partial", "stale",
            "ready", "partial", "stale",
            "ready", "blocked", "stale", "blocked", "stale", "blocked"
        ]

        for index in updates.indices {
            let expected = try ProjectDetailHeaderPresentationProjector.project(
                updates[index],
                validating: request
            )
            detail.yield(updates[index])
            await Self.waitUntil { model.detailPresentation == expected }
            #expect(model.detailStateLabel == labels[index])
            #expect(model.detailReadiness == readiness[index])
            #expect(model.detailDiagnostic == nil)
            if [11, 13].contains(index) {
                #expect(model.selectedProjectName == "Project Updated")
                #expect(model.selectedClientName == "Client Updated")
            } else if [0, 12, 14].contains(index) {
                #expect(model.selectedProjectName == "Project")
                #expect(model.selectedClientName == "Client")
            }
        }
        #expect(model.selectedProjectId == project.id)
        await model.stop()
    }

    @Test(arguments: DetailTerminationCase.allCases)
    func detailTerminationFailsClosed(_ terminal: DetailTerminationCase) async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let detail = ControlledStream<ProjectCoreDetailsUpdate>()
        if terminal.isBeforeFirstValue { terminal.finish(detail) }
        let details = DetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))
        let project = try Self.project("project-a")
        directory.yield(try Self.directory([project]))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: project.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }

        if !terminal.isBeforeFirstValue {
            let request = try #require(details.requests.first)
            detail.yield(try Self.update(request, .waiting(.loading)))
            await Self.waitUntil { model.detailStateLabel == "waiting" }
            terminal.finish(detail)
        }

        await Self.waitUntil { model.detailDiagnostic == terminal.diagnostic }
        #expect(model.detailPresentation == nil)
        #expect(model.detailStateLabel == "blocked")
        #expect(model.selectedProjectId == project.id)
        await Self.waitUntil { detail.terminationCount == 1 }
        #expect(detail.terminationCount == 1)
        await model.stop()
        #expect(detail.terminationCount == 1)
    }

    @Test("Mismatched detail evidence fails closed without leaking its error")
    func mismatchedDetailEvidenceFailsClosed() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let detail = ControlledStream<ProjectCoreDetailsUpdate>()
        let details = DetailWatchProbe(defaultSource: detail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))
        let project = try Self.project("project-a")
        directory.yield(try Self.directory([project]))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: project.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }

        let wrong = try ProjectCoreDetailsRequest(
            accountId: Self.accountId,
            projectId: ProjectID(validating: "project-other")
        )
        detail.yield(try Self.update(wrong, .waiting(.loading)))
        await Self.waitUntil { model.detailDiagnostic == "project_detail_evidence_invalid" }
        #expect(model.detailPresentation == nil)
        await Self.waitUntil { detail.terminationCount == 1 }
        #expect(detail.terminationCount == 1)
        await model.stop()
    }

    @Test("Rapid reselection drains A before B and ignores late or refreshed evidence")
    func rapidReselectionAndGenerationIsolation() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let detailA = ControlledStream<ProjectCoreDetailsUpdate>()
        let detailB = ControlledStream<ProjectCoreDetailsUpdate>()
        let detailBRefresh = ControlledStream<ProjectCoreDetailsUpdate>()
        let details = DetailWatchProbe(sources: [
            "project-a": [detailA],
            "project-b": [detailB, detailBRefresh]
        ])
        let model = Self.model()
        await model.start(runtime: Self.runtime(directory: directory, details: details))
        let projectA = try Self.project("project-a", name: "Project A", client: "client-a")
        let projectB = try Self.project("project-b", name: "Project B", client: "client-b")
        directory.yield(try Self.directory([projectA, projectB]))
        await Self.waitUntil { model.activeProjects.count == 2 }

        await model.select(projectId: projectA.id, segment: .active)
        await Self.waitUntil { details.requests.count == 1 }
        let requestA = details.requests[0]
        detailA.yield(try Self.snapshotUpdate(
            requestA,
            project: projectA,
            quality: .ready,
            complete: true,
            version: "a"
        ))
        await Self.waitUntil { model.selectedProjectId == projectA.id && model.detailStateLabel == "found" }

        await model.select(projectId: projectB.id, segment: .active)
        await Self.waitUntil { details.requests.count == 2 }
        #expect(detailA.terminationCount == 1)
        #expect(details.requestProjectIds == ["project-a", "project-b"])
        #expect(model.selectedProjectId == projectB.id)

        detailA.yield(try Self.update(requestA, .waiting(.blocked)))
        let requestB = details.requests[1]
        detailB.yield(try Self.update(requestB, .waiting(.loading)))
        await Self.waitUntil { model.detailStateLabel == "waiting" }
        #expect(model.selectedProjectId == projectB.id)

        let renamedB = try Self.project(
            "project-b",
            name: "Project B Renamed",
            client: "client-b"
        )
        directory.yield(try Self.directory([renamedB, projectA], version: "refreshed"))
        await Self.waitUntil { model.activeProjects.first?.projectId == projectB.id }
        #expect(details.requests.count == 2)
        #expect(model.selectedProjectName == "Project B")

        await model.select(projectId: projectB.id, segment: .active)
        await Self.waitUntil { details.requests.count == 3 }
        #expect(detailB.terminationCount == 1)
        #expect(model.selectedProjectName == "Project B Renamed")
        await model.stop()
    }

    @Test("Stop drains both observations and restart rejects post-stop evidence")
    func stopDrainageAndRestartIsolation() async throws {
        let firstDirectory = ControlledStream<ProjectListSnapshot>()
        let firstDetail = ControlledStream<ProjectCoreDetailsUpdate>()
        let firstDetails = DetailWatchProbe(defaultSource: firstDetail)
        let model = Self.model()
        await model.start(runtime: Self.runtime(
            directory: firstDirectory,
            details: firstDetails
        ))
        let firstProject = try Self.project("first")
        firstDirectory.yield(try Self.directory([firstProject]))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: firstProject.id, segment: .active)
        await Self.waitUntil { firstDetails.requests.count == 1 }

        await model.stop()
        #expect(firstDirectory.terminationCount == 1)
        #expect(firstDetail.terminationCount == 1)
        #expect(model.directoryStatus == "stopped • completeness unknown")
        #expect(model.detailStateLabel == "stopped")
        firstDirectory.yield(try Self.directory([Self.project("late")], version: "late"))
        #expect(model.activeProjects.isEmpty)

        let secondDirectory = ControlledStream<ProjectListSnapshot>()
        let secondDetail = ControlledStream<ProjectCoreDetailsUpdate>()
        await model.start(runtime: Self.runtime(
            directory: secondDirectory,
            details: DetailWatchProbe(defaultSource: secondDetail)
        ))
        #expect(model.directoryStatus == "loading • completeness unknown")
        let secondProject = try Self.project("second")
        secondDirectory.yield(try Self.directory([secondProject], version: "second"))
        await Self.waitUntil { model.activeProjects.first?.projectId == secondProject.id }
        firstDirectory.yield(try Self.directory([firstProject], version: "old-restart"))
        #expect(model.activeProjects.first?.projectId == secondProject.id)
        await model.stop()
        #expect(secondDirectory.terminationCount == 1)

        let beforeFirst = ControlledStream<ProjectListSnapshot>()
        await model.start(runtime: Self.runtime(directory: beforeFirst))
        await model.stop()
        #expect(beforeFirst.terminationCount == 1)
    }

    @Test("Restart rejects a late value from a noncooperative old detail source")
    func restartRejectsNoncooperativeOldDetailValue() async throws {
        let firstDirectory = ControlledStream<ProjectListSnapshot>()
        let oldDetail = DelayedValueDetailSource()
        let requests = DetailRequestRecorder()
        let firstRuntime = ProjectBrowsingStagingRuntime(
            watchProjects: { firstDirectory.stream },
            watchProject: { request in
                requests.record(request)
                return oldDetail.stream
            }
        )
        let model = Self.model()
        await model.start(runtime: firstRuntime)
        let firstProject = try Self.project("first", name: "First")
        firstDirectory.yield(try Self.directory([firstProject], version: "first"))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: firstProject.id, segment: .active)
        await Self.waitUntil { requests.requests.count == 1 }
        #expect(await Self.waitUntilAsync { await oldDetail.isWaiting })

        let secondDirectory = ControlledStream<ProjectListSnapshot>()
        let restart = Task { @MainActor in
            await model.start(runtime: Self.runtime(directory: secondDirectory))
        }
        await Self.waitUntil { model.directoryStatus == "loading • completeness unknown" }

        let oldUpdate = try Self.snapshotUpdate(
            requests.requests[0],
            project: firstProject,
            quality: .ready,
            complete: true,
            version: "late-old-detail"
        )
        await oldDetail.release(oldUpdate)
        await restart.value

        let secondProject = try Self.project("second", name: "Second")
        secondDirectory.yield(try Self.directory([secondProject], version: "second"))
        await Self.waitUntil { model.activeProjects.first?.projectId == secondProject.id }
        #expect(model.selectedProject == nil)
        #expect(model.detailPresentation == nil)
        #expect(model.detailStateLabel == "not selected")
        await model.stop()
    }

    @Test("Active to archived lifecycle movement preserves the exact note watch")
    func archiveLifecycleMovementPreservesNotes() async throws {
        let directory = ControlledStream<ProjectListSnapshot>()
        let detail = ControlledStream<ProjectCoreDetailsUpdate>()
        let notes = ControlledStream<ProjectNotePage>()
        let noteRequests = NoteRequestRecorder()
        let project = try Self.project("project-a")
        let runtime = ProjectBrowsingStagingRuntime(
            watchProjects: { directory.stream },
            watchProject: { _ in detail.stream },
            watchNotes: { request in
                noteRequests.record(request)
                return notes.stream
            }
        )
        let model = Self.model()
        await model.start(runtime: runtime)
        directory.yield(try Self.directory([project]))
        await Self.waitUntil { model.activeProjects.count == 1 }
        await model.select(projectId: project.id, segment: .active)
        await Self.waitUntil { noteRequests.requests.count == 1 }

        let request = try #require(noteRequests.requests.first)
        notes.yield(try Self.notePage(
            request: request,
            body: "Preserved",
            version: "before-archive"
        ))
        await Self.waitUntil { model.noteHistory.rows.first?.body == "Preserved" }

        let archived = try Self.project("project-a", lifecycle: .archived)
        directory.yield(try Self.directory([archived], version: "archived"))
        await Self.waitUntil {
            model.selectedProject?.projectLifecycle == .archived
        }
        notes.yield(try Self.notePage(
            request: request,
            body: "Preserved after archive",
            version: "after-archive"
        ))
        await Self.waitUntil {
            model.noteHistory.rows.first?.body == "Preserved after archive"
        }

        #expect(noteRequests.requests.count == 1)
        #expect(notes.terminationCount == 0)
        #expect(model.noteHistory.rows.first?.body == "Preserved after archive")
        #expect(model.selectedProjectId == project.id)
        await model.stop()
        #expect(notes.terminationCount == 1)
    }

    private static let accountId = try! AccountID(validating: "project-account")
    private static let t0 = Date(timeIntervalSince1970: 1_804_000_000)
    private static let t1 = Date(timeIntervalSince1970: 1_804_000_001)

    private static func model() -> ProjectBrowsingStagingExercise {
        ProjectBrowsingStagingExercise(accountId: accountId)
    }

    private static func runtime(
        directory: ControlledStream<ProjectListSnapshot>,
        details: DetailWatchProbe = DetailWatchProbe()
    ) -> ProjectBrowsingStagingRuntime {
        ProjectBrowsingStagingRuntime(
            watchProjects: { directory.stream },
            watchProject: { details.watch($0) }
        )
    }

    private static func project(
        _ id: String,
        account: String = "project-account",
        name: String = "Project",
        client: String = "client",
        clientName: String = "Client",
        lifecycle: DirectoryLifecycleState = .active,
        clientLifecycle: DirectoryLifecycleState = .active
    ) throws -> ProjectSummary {
        let accountId = try AccountID(validating: account)
        let clientId = try ClientID(validating: client)
        let client = try ClientSummary(
            id: clientId,
            accountId: accountId,
            displayName: ClientDisplayName(validating: clientName),
            lifecycle: clientLifecycle,
            createdAt: t0,
            updatedAt: t1
        )
        return try ProjectSummary(
            id: ProjectID(validating: id),
            accountId: accountId,
            clientId: clientId,
            client: client,
            displayName: ProjectDisplayName(validating: name),
            description: nil,
            lifecycle: lifecycle
        )
    }

    private static func directory(
        _ rows: [ProjectSummary],
        account: String = "project-account",
        visibleCount: Int? = nil,
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String = "directory"
    ) throws -> ProjectListSnapshot {
        try ProjectListSnapshot(
            accountId: AccountID(validating: account),
            local: ListLocalSnapshot(
                queryFingerprint: ListQueryFingerprint(
                    validating: String(repeating: String(version.utf8.count % 10), count: 64)
                ),
                rows: rows,
                visibleRowCountBeforeFiltering: visibleCount ?? rows.count,
                isCompleteForQuery: complete,
                quality: quality,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: t1.addingTimeInterval(Double(version.utf8.count))
            )
        )
    }

    private static func detailRow(
        project: ProjectSummary
    ) throws -> ProjectCoreDetailsSnapshot {
        try ProjectCoreDetailsSnapshot(
            project: project,
            locallyObservedRevision: ExpectedProjectRevision(7)
        )
    }

    private static func notePage(
        request: ProjectNotePageRequest,
        body: String,
        version: String
    ) throws -> ProjectNotePage {
        let note = try ProjectNoteSnapshot(
            id: ProjectNoteID(validating: "note-a"),
            accountId: request.accountId,
            projectId: request.projectId,
            content: .visible(ProjectNoteText(validating: body)),
            source: ProjectNoteSource(validating: "text"),
            createdByPrincipalId: PrincipalID(validating: "principal-a"),
            creatorDisplayName: nil,
            createdAt: t1,
            revision: 1
        )
        return try ProjectNotePage(
            request: request,
            local: ListLocalSnapshot(
                queryFingerprint: request.queryFingerprint,
                rows: [note],
                visibleRowCountBeforeFiltering: 1,
                isCompleteForQuery: true,
                quality: .ready,
                localDataVersion: LocalDataVersion(validating: version),
                asOf: t1
            ),
            isCompleteForProjectHistory: true,
            nextCursor: nil
        )
    }

    private static func detailLocal(
        request: ProjectCoreDetailsRequest,
        rows: [ProjectCoreDetailsSnapshot],
        complete: Bool = true,
        quality: ListSnapshotQuality = .ready,
        version: String
    ) throws -> ProjectCoreDetailsLocalSnapshot {
        try ProjectCoreDetailsLocalSnapshot(
            request: request,
            rows: rows,
            visibleRowCountBeforeFiltering: rows.count,
            isCompleteForQuery: complete,
            quality: quality,
            localDataVersion: LocalDataVersion(validating: version),
            asOf: t1.addingTimeInterval(Double(version.utf8.count))
        )
    }

    private static func update(
        _ request: ProjectCoreDetailsRequest,
        _ state: ProjectCoreDetailsUpdateState
    ) throws -> ProjectCoreDetailsUpdate {
        try ProjectCoreDetailsUpdate(request: request, state: state)
    }

    private static func snapshotUpdate(
        _ request: ProjectCoreDetailsRequest,
        project: ProjectSummary,
        quality: ListSnapshotQuality,
        complete: Bool,
        version: String
    ) throws -> ProjectCoreDetailsUpdate {
        try update(
            request,
            .snapshot(detailLocal(
                request: request,
                rows: [detailRow(project: project)],
                complete: complete,
                quality: quality,
                version: version
            ))
        )
    }

    private static func emptyUpdate(
        _ request: ProjectCoreDetailsRequest,
        quality: ListSnapshotQuality,
        complete: Bool,
        version: String
    ) throws -> ProjectCoreDetailsUpdate {
        try update(
            request,
            .snapshot(detailLocal(
                request: request,
                rows: [],
                complete: complete,
                quality: quality,
                version: version
            ))
        )
    }

    private static func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for Project browsing state")
    }

    private static func waitUntilAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

enum DirectoryTerminationCase: String, CaseIterable, Sendable {
    case throwBeforeFirst
    case throwAfterFirst
    case cancelBeforeFirst
    case cancelAfterFirst
    case completeBeforeFirst
    case completeAfterFirst

    var isBeforeFirstValue: Bool {
        switch self {
        case .throwBeforeFirst, .cancelBeforeFirst, .completeBeforeFirst: true
        case .throwAfterFirst, .cancelAfterFirst, .completeAfterFirst: false
        }
    }

    var diagnostic: String {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst: "project_directory_local_failed"
        case .cancelBeforeFirst, .cancelAfterFirst: "project_directory_source_cancelled"
        case .completeBeforeFirst, .completeAfterFirst: "project_directory_source_completed"
        }
    }

    fileprivate func finish(_ stream: ControlledStream<ProjectListSnapshot>) {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst:
            stream.finish(throwing: SourceFailure.upstream)
        case .cancelBeforeFirst, .cancelAfterFirst:
            stream.finish(throwing: CancellationError())
        case .completeBeforeFirst, .completeAfterFirst:
            stream.finish()
        }
    }
}

enum DetailTerminationCase: String, CaseIterable, Sendable {
    case throwBeforeFirst
    case throwAfterFirst
    case cancelBeforeFirst
    case cancelAfterFirst
    case completeBeforeFirst
    case completeAfterFirst

    var isBeforeFirstValue: Bool {
        switch self {
        case .throwBeforeFirst, .cancelBeforeFirst, .completeBeforeFirst: true
        case .throwAfterFirst, .cancelAfterFirst, .completeAfterFirst: false
        }
    }

    var diagnostic: String {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst: "project_detail_local_failed"
        case .cancelBeforeFirst, .cancelAfterFirst: "project_detail_source_cancelled"
        case .completeBeforeFirst, .completeAfterFirst: "project_detail_source_completed"
        }
    }

    fileprivate func finish(_ stream: ControlledStream<ProjectCoreDetailsUpdate>) {
        switch self {
        case .throwBeforeFirst, .throwAfterFirst:
            stream.finish(throwing: SourceFailure.upstream)
        case .cancelBeforeFirst, .cancelAfterFirst:
            stream.finish(throwing: CancellationError())
        case .completeBeforeFirst, .completeAfterFirst:
            stream.finish()
        }
    }
}

private enum SourceFailure: Error { case upstream }

private final class ControlledStream<Value: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Value, Error>
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    private let termination = TerminationProbe()

    init() {
        var captured: AsyncThrowingStream<Value, Error>.Continuation?
        let termination = termination
        stream = AsyncThrowingStream { continuation in
            captured = continuation
            continuation.onTermination = { _ in termination.record() }
        }
        continuation = captured!
    }

    var terminationCount: Int { termination.count }

    func yield(_ value: Value) {
        continuation.yield(value)
    }

    func finish() {
        continuation.finish()
    }

    func finish(throwing error: Error) {
        continuation.finish(throwing: error)
    }
}

private final class TerminationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCount = 0

    var count: Int {
        lock.withLock { recordedCount }
    }

    func record() {
        lock.withLock { recordedCount += 1 }
    }
}

private final class NoteRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProjectNotePageRequest] = []

    var requests: [ProjectNotePageRequest] { lock.withLock { values } }

    func record(_ request: ProjectNotePageRequest) {
        lock.withLock { values.append(request) }
    }
}

private final class DetailWatchProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [ProjectCoreDetailsRequest] = []
    private var sources: [String: [ControlledStream<ProjectCoreDetailsUpdate>]]
    private let defaultSource: ControlledStream<ProjectCoreDetailsUpdate>?

    init(
        sources: [String: [ControlledStream<ProjectCoreDetailsUpdate>]] = [:],
        defaultSource: ControlledStream<ProjectCoreDetailsUpdate>? = nil
    ) {
        self.sources = sources
        self.defaultSource = defaultSource
    }

    convenience init(defaultSource: ControlledStream<ProjectCoreDetailsUpdate>) {
        self.init(sources: [:], defaultSource: defaultSource)
    }

    var requests: [ProjectCoreDetailsRequest] {
        lock.withLock { recordedRequests }
    }

    var requestProjectIds: [String] {
        requests.map(\.projectId.rawValue)
    }

    func watch(
        _ request: ProjectCoreDetailsRequest
    ) -> AsyncThrowingStream<ProjectCoreDetailsUpdate, Error> {
        lock.withLock {
            recordedRequests.append(request)
            let key = request.projectId.rawValue
            if var queued = sources[key], !queued.isEmpty {
                let source = queued.removeFirst()
                sources[key] = queued
                return source.stream
            }
            if let defaultSource { return defaultSource.stream }
            return AsyncThrowingStream { $0.finish(throwing: SourceFailure.upstream) }
        }
    }
}

private final class DetailRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProjectCoreDetailsRequest] = []

    var requests: [ProjectCoreDetailsRequest] {
        lock.withLock { recorded }
    }

    func record(_ request: ProjectCoreDetailsRequest) {
        lock.withLock { recorded.append(request) }
    }
}

private final class DelayedCancellationDetailSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<ProjectCoreDetailsUpdate, Error>
    private let gate: DelayedDetailNextGate
    private let termination = TerminationProbe()

    init() {
        let gate = DelayedDetailNextGate()
        let termination = termination
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: {
            do {
                return try await gate.next()
            } catch {
                termination.record()
                throw error
            }
        })
    }

    var terminationCount: Int { termination.count }

    var isWaiting: Bool {
        get async { await gate.isWaiting }
    }

    func releaseCancellation() async {
        await gate.releaseCancellation()
    }
}

private final class DelayedValueDetailSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<ProjectCoreDetailsUpdate, Error>
    private let gate: DelayedValueDetailNextGate

    init() {
        let gate = DelayedValueDetailNextGate()
        self.gate = gate
        stream = AsyncThrowingStream(unfolding: {
            await gate.next()
        })
    }

    var isWaiting: Bool {
        get async { await gate.isWaiting }
    }

    func release(_ value: ProjectCoreDetailsUpdate) async {
        await gate.release(value)
    }
}

private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var finished = false

    var didStart: Bool { lock.withLock { started } }
    var didFinish: Bool { lock.withLock { finished } }

    func markStarted() {
        lock.withLock { started = true }
    }

    func markFinished() {
        lock.withLock { finished = true }
    }
}

private actor DelayedDetailNextGate {
    private var continuation: CheckedContinuation<ProjectCoreDetailsUpdate?, Error>?

    var isWaiting: Bool { continuation != nil }

    func next() async throws -> ProjectCoreDetailsUpdate? {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func releaseCancellation() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor DelayedValueDetailNextGate {
    private var continuation: CheckedContinuation<ProjectCoreDetailsUpdate?, Never>?

    var isWaiting: Bool { continuation != nil }

    func next() async -> ProjectCoreDetailsUpdate? {
        await withCheckedContinuation { continuation = $0 }
    }

    func release(_ value: ProjectCoreDetailsUpdate) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
