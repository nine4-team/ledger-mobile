import Foundation

/// Pure presentation: no queries, authorization or recomputation of totals.
/// One rectangular CSV contains metadata, Space parents, Items, group totals and
/// report totals. Empty monetary cells mean unknown/not applicable, never zero.
/// Amounts are exact signed minor-unit decimal strings, without floating point.
/// User text with formula/control prefixes gains a leading apostrophe for safer
/// spreadsheet opening; this presentation escape does not modify the snapshot.
public enum PropertyManagementReportCSV {
    public static func render(_ snapshot: PropertyManagementReportSnapshot) -> String {
        let columns = ["row_type", "account_id", "project_id", "space_id", "space_name",
                       "item_id", "placement_id", "item_name", "sku", "revision", "currency",
                       "market_value_minor_units", "item_count", "known_market_value_subtotal_minor_units",
                       "unknown_market_value_count", "total_market_value_minor_units", "metadata_key", "metadata_value"]
        var lines = [columns.map(quote).joined(separator: ",")]
        func emit(_ values: [String: String]) {
            var row = values
            row["account_id"] = text(snapshot.project.accountId.rawValue)
            row["project_id"] = text(snapshot.project.projectId.rawValue)
            lines.append(columns.map { quote(row[$0] ?? "") }.joined(separator: ","))
        }
        func metadata(_ key: String, _ value: String, userText: Bool = true) {
            emit(["row_type": "metadata", "metadata_key": key,
                  "metadata_value": userText ? text(value) : value])
        }
        metadata("report_kind", snapshot.reportKind)
        metadata("project_name", snapshot.project.name, userText: true)
        metadata("property_address", snapshot.project.address ?? "", userText: true)
        metadata("property_address_known", snapshot.project.address == nil ? "false" : "true")
        metadata("project_revision", String(snapshot.project.revision))
        metadata("snapshot_id", snapshot.reference.snapshotID.rawValue)
        metadata("snapshot_hash", snapshot.reference.snapshotHash.rawValue)
        metadata("source_set_hash", snapshot.sourceSetHash.rawValue)
        metadata("visibility_scope_id", snapshot.reference.visibilityScopeID.rawValue)
        metadata("profile_version", snapshot.reference.profileVersion.rawValue)
        metadata("authority_version", snapshot.provenance.authorityVersion.rawValue)
        metadata("source_kind", snapshot.provenance.source.kind)
        if let version = snapshot.provenance.localDataVersion {
            metadata("local_data_version", version.rawValue, userText: true)
        }
        metadata("principal_id", snapshot.provenance.principalId.rawValue, userText: true)
        metadata("as_of_epoch_milliseconds", String(snapshot.provenance.asOf.rawValue))
        if let syncedAt = snapshot.provenance.lastSyncedAt {
            metadata("last_synced_at_epoch_milliseconds", String(syncedAt.rawValue))
        }
        metadata("currency", snapshot.currency.rawValue)
        metadata("readiness", snapshot.provenance.readiness.rawValue)
        for space in snapshot.spaces {
            emit(["row_type": "space", "space_id": text(space.spaceId.rawValue),
                  "space_name": text(space.name), "revision": String(space.revision)])
        }
        func totals(_ totals: PropertyManagementReportTotals, type: String,
                    spaceId: SpaceID? = nil, spaceName: String = "") {
            emit(["row_type": type, "space_id": text(spaceId?.rawValue ?? ""), "space_name": text(spaceName),
                  "currency": totals.knownMarketValueSubtotal.currency.rawValue,
                  "item_count": String(totals.itemCount),
                  "known_market_value_subtotal_minor_units": String(totals.knownMarketValueSubtotal.minorUnits),
                  "unknown_market_value_count": String(totals.unknownMarketValueCount),
                  "total_market_value_minor_units": totals.totalMarketValue.map { String($0.minorUnits) } ?? ""])
        }
        for group in snapshot.groups {
            for item in group.rows {
                emit(["row_type": "item", "space_id": text(item.spaceId?.rawValue ?? ""),
                      "space_name": text(group.name), "item_id": text(item.itemId.rawValue),
                      "placement_id": text(item.placementId.rawValue), "item_name": text(item.name),
                      "sku": text(item.sku ?? ""), "revision": String(item.itemRevision),
                      "currency": snapshot.currency.rawValue,
                      "market_value_minor_units": item.marketValue.map { String($0.minorUnits) } ?? ""])
            }
            totals(group.totals, type: "group_total", spaceId: group.spaceId, spaceName: group.name)
        }
        totals(snapshot.totals, type: "report_total")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func text(_ value: String) -> String {
        let significant = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formula = significant.first.map { "=+-@".contains($0) } ?? false
        let controlPrefix = value.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? false
        return formula || controlPrefix ? "'" + value : value
    }
}
