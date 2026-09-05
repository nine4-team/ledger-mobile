import PowerSync

public enum LedgerPowerSyncTable {
    public static let principals = "spike_principals"
    public static let accounts = "spike_accounts"
    public static let memberships = "spike_account_memberships"
    public static let clients = "spike_clients"
    public static let pendingClients = "spike_pending_clients"
    public static let clientCommands = "spike_client_commands"
    public static let budgetCategories = "spike_budget_categories"
    public static let spaces = "spike_spaces"
    public static let projects = "spike_projects"
    public static let projectNotes = "spike_project_notes"
    public static let pendingProjects = "spike_pending_projects"
    public static let projectCategoryAllocations = "spike_project_category_allocations"
    public static let pendingProjectCategoryAllocations = "spike_pending_project_category_allocations"
    public static let projectCommands = "spike_project_commands"
    public static let projectArchiveCommands = "spike_project_archive_commands"
    public static let projectArchiveOverlays = "spike_project_archive_overlays"
    public static let clientArchiveCommands = "spike_client_archive_commands"
    public static let clientArchiveOverlays = "spike_client_archive_overlays"
    public static let localOperations = "spike_local_operations"
    public static let pendingWorkObservations = "spike_pending_work_observations"
    public static let operationResults = "spike_operation_results"
}

public enum LedgerPowerSyncSchema {
    public static let schema = Schema(
        Table(
            name: LedgerPowerSyncTable.principals,
            columns: [.text("auth_user_id")]
        ),
        Table(
            name: LedgerPowerSyncTable.accounts,
            columns: [.text("display_name")]
        ),
        Table(
            name: LedgerPowerSyncTable.memberships,
            columns: [
                .text("account_id"), .text("principal_id"), .text("role"),
                .text("state"), .integer("can_manage_clients"),
                .integer("can_manage_projects"),
                .integer("can_manage_project_budgets"), .text("financial_access")
            ],
            indexes: [
                .ascending(
                    name: "membership_principal_account",
                    columns: ["principal_id", "account_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.clients,
            columns: [
                .text("account_id"), .text("display_name"), .text("lifecycle"),
                .integer("revision"), .integer("created_at_ms"),
                .integer("updated_at_ms"), .text("created_by_principal_id")
            ],
            indexes: [
                .ascending(
                    name: "client_account_identity",
                    columns: ["account_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.pendingClients,
            columns: [
                .text("account_id"), .text("display_name"), .text("lifecycle"),
                .integer("revision"), .integer("created_at_ms"),
                .integer("updated_at_ms"), .text("created_by_principal_id"),
                .text("operation_id")
            ],
            indexes: [
                .ascending(name: "pending_client_account", columns: ["account_id"]),
                .ascending(name: "pending_client_operation", columns: ["operation_id"])
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.clientCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .integer("client_created_at_ms"),
                .text("client_id"), .text("display_name"), .text("fingerprint"),
                .text("envelope_json")
            ],
            insertOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.budgetCategories,
            columns: [
                .text("account_id"), .text("display_name"), .text("kind"),
                .text("lifecycle"), .integer("is_system"),
                .integer("excludes_from_overall_budget"),
                .text("visibility_class"), .integer("presentation_order"),
                .integer("revision"),
                .integer("created_at_ms"), .integer("updated_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "budget_category_account_order",
                    columns: ["account_id", "presentation_order"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.spaces,
            columns: [
                .text("account_id"), .text("scope_kind"), .text("project_id"),
                .text("display_name"), .text("lifecycle"), .integer("revision")
            ],
            indexes: [
                .ascending(
                    name: "space_assignment_destination_scope",
                    columns: ["account_id", "scope_kind", "project_id", "lifecycle"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.projects,
            columns: [
                .text("account_id"), .text("client_id"), .text("display_name"),
                .text("description"), .text("lifecycle"), .integer("revision"),
                .integer("created_at_ms"), .integer("updated_at_ms"),
                .text("created_by_principal_id")
            ],
            indexes: [
                .ascending(name: "project_account", columns: ["account_id"]),
                .ascending(
                    name: "project_account_client",
                    columns: ["account_id", "client_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.projectNotes,
            columns: [
                .text("account_id"), .text("project_id"), .text("keyset_id"),
                .text("content_kind"),
                .text("note_text"), .text("source"),
                .text("created_by_principal_id"), .text("creator_display_name"),
                .integer("created_at_ms"), .text("revision"),
                .text("last_edited_by_principal_id"), .integer("last_edited_at_ms"),
                .text("deleted_by_principal_id"), .integer("deleted_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "project_note_history_page",
                    columns: ["account_id", "project_id", "created_at_ms", "keyset_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.pendingProjects,
            columns: [
                .text("account_id"), .text("client_id"), .text("display_name"),
                .text("description"), .text("lifecycle"), .integer("revision"),
                .integer("created_at_ms"), .integer("updated_at_ms"),
                .text("created_by_principal_id"), .text("operation_id")
            ],
            indexes: [
                .ascending(name: "pending_project_account", columns: ["account_id"]),
                .ascending(name: "pending_project_operation", columns: ["operation_id"])
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.projectCategoryAllocations,
            columns: [
                .text("account_id"), .text("project_id"), .text("category_id"),
                .integer("allocation_minor_units"), .text("allocation_currency"),
                .integer("revision"), .integer("created_at_ms"),
                .integer("updated_at_ms"), .text("created_by_principal_id")
            ],
            indexes: [
                .ascending(
                    name: "project_allocation_project",
                    columns: ["account_id", "project_id"]
                ),
                .ascending(
                    name: "project_allocation_category",
                    columns: ["account_id", "category_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.pendingProjectCategoryAllocations,
            columns: [
                .text("account_id"), .text("project_id"), .text("category_id"),
                .integer("allocation_minor_units"), .text("allocation_currency"),
                .integer("revision"), .integer("created_at_ms"),
                .integer("updated_at_ms"), .text("created_by_principal_id"),
                .text("operation_id")
            ],
            indexes: [
                .ascending(
                    name: "pending_project_allocation_project",
                    columns: ["account_id", "project_id"]
                ),
                .ascending(
                    name: "pending_project_allocation_operation",
                    columns: ["operation_id"]
                )
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.projectCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .integer("project_created_at_ms"),
                .text("project_id"), .text("client_selection_kind"),
                .text("client_id"), .text("new_client_display_name"),
                .text("project_display_name"), .text("description"),
                .text("category_allocations_json"), .text("fingerprint"),
                .text("envelope_json")
            ],
            insertOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.projectArchiveCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .integer("client_created_at_ms"),
                .text("project_id"), .text("expected_revision"),
                .text("fingerprint"), .text("envelope_json")
            ],
            insertOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.projectArchiveOverlays,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("project_id"), .text("operation_id"),
                .text("fingerprint"), .text("expected_revision"),
                .integer("projected_revision"), .text("lifecycle"),
                .integer("accepted_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "project_archive_overlay_account_project",
                    columns: ["account_id", "project_id"]
                ),
                .ascending(
                    name: "project_archive_overlay_operation",
                    columns: ["operation_id"]
                )
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.clientArchiveCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .integer("client_created_at_ms"),
                .text("client_id"), .text("expected_revision"),
                .text("fingerprint"), .text("envelope_json")
            ],
            insertOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.clientArchiveOverlays,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("client_id"), .text("operation_id"),
                .text("fingerprint"), .text("expected_revision"),
                .integer("projected_revision"), .text("lifecycle"),
                .integer("accepted_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "client_archive_overlay_account_client",
                    columns: ["account_id", "client_id"]
                ),
                .ascending(
                    name: "client_archive_overlay_operation",
                    columns: ["operation_id"]
                )
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.localOperations,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .text("fingerprint"),
                .text("subject_id"), .text("local_state"),
                .integer("accepted_at_ms"), .integer("updated_at_ms"),
                .text("command_type"), .text("command_expected_revision"),
                .text("command_envelope_json"), .text("terminal_phase"),
                .text("terminal_result_code"), .text("terminal_error_code"),
                .text("terminal_envelope_sha256"), .text("terminal_request_sha256"),
                .integer("terminal_server_received_at_ms"),
                .integer("terminal_completed_at_ms")
            ],
            indexes: [
                .ascending(name: "local_operation_account", columns: ["account_id"]),
                .ascending(name: "local_operation_state", columns: ["local_state"])
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.pendingWorkObservations,
            columns: [
                .text("environment"), .text("principal_id"), .text("account_id"),
                .text("evidence_sha256"), .integer("snapshot_revision"),
                .integer("observed_at_ms")
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.operationResults,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("command_type"), .text("contract_version"),
                .text("command_fingerprint"), .text("envelope_sha256"),
                .text("request_sha256"), .text("subject_id"), .text("phase"),
                .text("result_code"),
                .text("error_code"), .integer("client_created_at_ms"),
                .integer("server_received_at_ms"), .integer("completed_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "operation_account_identity",
                    columns: ["account_id"]
                )
            ]
        )
    )
}
