import PowerSync

public enum LedgerPowerSyncTable {
    public static let principals = "spike_principals"
    public static let accounts = "spike_accounts"
    public static let accountBusinessProfiles = "spike_account_business_profiles"
    public static let memberships = "spike_account_memberships"
    public static let clients = "spike_clients"
    public static let pendingClients = "spike_pending_clients"
    public static let clientCommands = "spike_client_commands"
    public static let budgetCategories = "spike_budget_categories"
    public static let spaces = "spike_spaces"
    public static let items = "spike_items"
    public static let itemImageSets = "item_image_sets"
    public static let itemImageReferences = "item_image_references"
    public static let itemImageObjects = "item_image_objects"
    public static let itemCardThumbnails = "item_card_thumbnails"
    public static let itemPlacements = "spike_item_placements"
    public static let itemClientPaymentConnections = "item_client_payment_connections"
    public static let itemChargeOccurrences = "item_charge_occurrences"
    public static let collectedInvoiceLines = "collected_invoice_lines"
    public static let collectedInvoices = "collected_invoices"
    public static let itemProjectCategories = "spike_item_project_categories"
    public static let spaceCoreDetails = "spike_space_core_details"
    public static let spaceChecklists = "spike_space_checklists"
    public static let spaceChecklistItems = "spike_space_checklist_items"
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
    public static let itemSpaceAssignmentCommands = "spike_item_space_assignment_commands"
    public static let itemSpaceClearingCommands = "spike_item_space_clearing_commands"
    public static let spaceChecklistRevisionCommands = "spike_space_checklist_revision_commands"
    public static let spaceChecklistRevisionOverlays = "spike_space_checklist_revision_overlays"
    public static let localOperations = "spike_local_operations"
    public static let pendingWorkObservations = "spike_pending_work_observations"
    public static let operationResults = "spike_operation_results"
}

public enum LedgerPowerSyncSchema {
    public static let schema = Schema(
        Table(name: LedgerPowerSyncTable.itemChargeOccurrences,
            columns: [.text("account_id"), .text("project_id"), .text("item_id"), .text("placement_id"),
                      .text("category_id"), .text("amount_minor_units"), .text("currency"),
                      .integer("revision"), .text("withdrawn_at")],
            indexes: [.ascending(name: "charge_project", columns: ["account_id", "project_id", "placement_id"])]),
        Table(name: LedgerPowerSyncTable.collectedInvoiceLines,
            columns: [.text("account_id"), .text("invoice_id"), .text("source_kind"), .text("source_id"),
                      .text("item_id"), .integer("source_revision"), .text("category_id"),
                      .text("signed_amount_minor_units"), .text("currency")],
            indexes: [.ascending(name: "collected_line_source", columns: ["source_kind", "source_id"])]),
        Table(name: LedgerPowerSyncTable.collectedInvoices,
            columns: [.text("account_id"), .text("project_id"), .text("client_id"), .integer("sealed")]),
        Table(name: LedgerPowerSyncTable.itemClientPaymentConnections,
            columns: [.text("account_id"), .text("project_id"), .text("client_id"), .text("item_id"),
                      .text("placement_id"), .text("transaction_id"), .text("transaction_type"),
                      .text("transaction_role"), .text("ended_at")],
            indexes: [.ascending(name: "item_payment_project", columns: ["account_id", "project_id", "placement_id"])]),
        Table(
            name: LedgerPowerSyncTable.items,
            columns: [.text("account_id"), .text("name"), .text("description"), .text("sku"),
                      .text("workflow_status"), .integer("bookmark"),
                      .text("source"), .text("current_source"), .text("notes"),
                      .text("market_value_minor_units"), .text("market_value_currency"),
                      .integer("revision"),
                      .text("created_at"), .text("created_by_principal_id")],
            indexes: [.ascending(name: "item_account", columns: ["account_id"])]
        ),
        Table(name: LedgerPowerSyncTable.itemImageSets, columns: [.text("account_id"),.text("item_id"),
            .text("revision"),.integer("expected_count")]),
        Table(name: LedgerPowerSyncTable.itemImageReferences, columns: [.text("account_id"),.text("item_id"),
            .text("attachment_id"),.text("set_revision"),.integer("position"),.integer("is_primary")],
            indexes: [.ascending(name: "image_reference_item", columns: ["account_id","item_id"])]),
        Table(name: LedgerPowerSyncTable.itemImageObjects, columns: [.text("account_id"),.text("content_sha256"),
            .text("byte_count"),.text("media_type"),.text("storage_path")]),
        Table(name: LedgerPowerSyncTable.itemCardThumbnails, columns: [.text("account_id"),
            .text("original_attachment_id"),.text("thumbnail_attachment_id"),.text("recipe"),
            .integer("pixel_width"),.integer("pixel_height")],
            indexes: [.ascending(name: "thumbnail_original", columns: ["account_id","original_attachment_id"])]),
        Table(
            name: LedgerPowerSyncTable.itemPlacements,
            columns: [.text("account_id"), .text("item_id"), .text("scope_kind"),
                      .text("project_id"), .text("space_id"), .text("started_at"),
                      .text("started_by_principal_id"), .text("ended_at"),
                      .text("ended_by_principal_id")],
            indexes: [
                .ascending(name: "placement_item", columns: ["account_id", "item_id", "ended_at"]),
                .ascending(name: "placement_scope", columns: ["account_id", "scope_kind", "project_id", "ended_at"])
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.principals,
            columns: [.text("auth_user_id")]
        ),
        Table(
            name: LedgerPowerSyncTable.accounts,
            columns: [.text("display_name")]
        ),
        Table(
            name: LedgerPowerSyncTable.accountBusinessProfiles,
            columns: [.text("account_id"), .text("logo_attachment_id"),
                      .text("logo_content_sha256"), .text("logo_byte_count"),
                      .text("logo_media_type"), .text("logo_storage_path"), .text("revision")]
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
            name: LedgerPowerSyncTable.itemProjectCategories,
            columns: [.text("account_id"), .text("project_id"), .text("item_id"),
                .text("category_id"), .integer("revision")],
            indexes: [.ascending(name: "item_category_project", columns: ["account_id", "project_id"])]
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
            name: LedgerPowerSyncTable.spaceCoreDetails,
            columns: [
                .text("account_id"), .text("notes"),
                .integer("created_at_ms"), .integer("updated_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "space_core_details_account",
                    columns: ["account_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.spaceChecklists,
            columns: [
                .text("account_id"), .text("space_id"), .text("checklist_id"),
                .text("name"), .integer("presentation_order")
            ],
            indexes: [
                .ascending(
                    name: "space_checklist_space_order",
                    columns: ["account_id", "space_id", "presentation_order"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.spaceChecklistItems,
            columns: [
                .text("account_id"), .text("space_id"), .text("checklist_id"),
                .text("item_id"), .text("item_text"), .integer("is_checked"),
                .integer("presentation_order")
            ],
            indexes: [
                .ascending(
                    name: "space_checklist_item_checklist_order",
                    columns: [
                        "account_id", "space_id", "checklist_id",
                        "presentation_order"
                    ]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.projects,
            columns: [
                .text("account_id"), .text("client_id"), .text("display_name"),
                .text("description"), .text("legacy_notes"), .text("property_address"), .text("lifecycle"), .integer("revision"),
                .text("category_configuration_revision"),
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
                .text("original_creator_id"),
                .integer("created_at_ms"), .integer("created_at_submillis"), .text("revision"),
                .text("last_edited_by_principal_id"), .integer("last_edited_at_ms"),
                .integer("last_edited_at_submillis"),
                .text("deleted_by_principal_id"), .integer("deleted_at_ms"),
                .integer("deleted_at_submillis")
            ],
            indexes: [
                .ascending(
                    name: "project_note_history_page",
                    columns: ["account_id", "project_id", "created_at_ms", "created_at_submillis", "keyset_id"]
                )
            ]
        ),
        Table(
            name: LedgerPowerSyncTable.pendingProjects,
            columns: [
                .text("account_id"), .text("client_id"), .text("display_name"),
                .text("description"), .text("lifecycle"), .integer("revision"),
                .text("category_configuration_revision"),
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
            name: LedgerPowerSyncTable.itemSpaceAssignmentCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .text("destination_space_id"),
                .text("scope_kind"), .text("project_id"),
                .text("expected_space_revision"), .text("items_json"),
                .text("fingerprint"), .text("command_json"),
                .integer("accepted_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "item_space_assignment_command_account",
                    columns: ["account_id"]
                )
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.itemSpaceClearingCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .text("scope_kind"),
                .text("project_id"), .text("items_json"),
                .text("fingerprint"), .text("command_json"),
                .integer("accepted_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "item_space_clearing_command_account",
                    columns: ["account_id"]
                )
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.spaceChecklistRevisionCommands,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .integer("client_created_at_ms"),
                .text("space_id"), .text("expected_revision"),
                .text("collection_json"), .text("fingerprint"),
                .text("envelope_json")
            ],
            insertOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.spaceChecklistRevisionOverlays,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("space_id"), .text("operation_id"),
                .text("fingerprint"), .text("expected_revision"),
                .integer("projected_revision"), .text("collection_json"),
                .integer("accepted_at_ms")
            ],
            indexes: [
                .ascending(
                    name: "space_checklist_revision_overlay_account_space",
                    columns: ["account_id", "space_id"]
                ),
                .ascending(
                    name: "space_checklist_revision_overlay_operation",
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
                .integer("terminal_completed_at_ms"),
                .integer("checklist_readback_revision")
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
