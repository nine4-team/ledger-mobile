import PowerSync

public enum LedgerPowerSyncTable {
    public static let principals = "spike_principals"
    public static let accounts = "spike_accounts"
    public static let memberships = "spike_account_memberships"
    public static let clients = "spike_clients"
    public static let clientCommands = "spike_client_commands"
    public static let localOperations = "spike_local_operations"
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
                .text("state"), .integer("can_manage_clients")
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
                .integer("updated_at_ms"), .text("created_by_principal_id"),
                .text("pending_operation_id")
            ],
            indexes: [
                .ascending(
                    name: "client_account_identity",
                    columns: ["account_id"]
                )
            ]
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
            name: LedgerPowerSyncTable.localOperations,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("contract_version"), .text("fingerprint"),
                .text("subject_id"), .text("local_state"),
                .integer("accepted_at_ms"), .integer("updated_at_ms")
            ],
            indexes: [
                .ascending(name: "local_operation_account", columns: ["account_id"]),
                .ascending(name: "local_operation_state", columns: ["local_state"])
            ],
            localOnly: true
        ),
        Table(
            name: LedgerPowerSyncTable.operationResults,
            columns: [
                .text("account_id"), .text("actor_principal_id"),
                .text("command_type"), .text("contract_version"),
                .text("command_fingerprint"), .text("envelope_sha256"),
                .text("subject_id"), .text("phase"), .text("result_code"),
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
