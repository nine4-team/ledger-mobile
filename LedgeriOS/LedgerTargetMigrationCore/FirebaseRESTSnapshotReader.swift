import Foundation

/// Reads the private, typed REST snapshot produced by the read-only exporter.
/// Parsing grants no import eligibility; callers still run semantic reconciliation.
package enum FirebaseRESTSnapshotReader {
    package static func read(_ data: Data, accountPath: String) throws -> [FirebaseSourceDocument] {
        let decoder = JSONDecoder()
        guard let separator = accountPath.range(of: "/documents/") else { throw Failure.scope }
        decoder.userInfo[CodingUserInfoKey(rawValue: "sourcePrefix")!] = String(accountPath[..<separator.upperBound])
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        guard snapshot.account == accountPath else { throw Failure.scope }
        let prefix = "projects/\(snapshot.sourceProject)/databases/(default)/documents/"
        guard accountPath.hasPrefix(prefix + "accounts/") else { throw Failure.scope }
        let accountSegments = String(accountPath.dropFirst(prefix.count)).components(separatedBy: "/")
        guard accountSegments.count == 2, !accountSegments[1].isEmpty else { throw Failure.scope }
        var seen = Set<String>()
        return try snapshot.documents.map { document in
            guard document.name.hasPrefix(accountPath + "/"), seen.insert(document.name).inserted else { throw Failure.scope }
            let segments = String(document.name.dropFirst(prefix.count)).components(separatedBy: "/")
            guard segments.count >= 4, segments.count.isMultiple(of: 2), !segments.contains("") else { throw Failure.scope }
            let value = FirebaseSourceValue.map(document.fields.keys.sorted().map {
                .init(key: $0, value: document.fields[$0]!.value)
            })
            return FirebaseSourceDocument(accountScopeID: accountSegments[1], documentPathSegments: segments,
                entityCode: segments[segments.count - 2], evidenceKind: .record,
                fields: try value.validated(), sourceRecordID: segments.joined(separator: "/"))
        }
    }
    private enum Failure: Error { case scope, value, timestamp }
    private struct Snapshot: Decodable {
        let account: String
        let sourceProject: String
        let documents: [Document]
    }
    private struct Document: Decodable {
        let name: String
        let fields: [String: Value]
    }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private struct Values: Decodable { let values: [Value]? }
    private struct Fields: Decodable { let fields: [String: Value]? }
    private struct Coordinates: Decodable { let latitude: Double; let longitude: Double }
    private struct Value: Decodable {
        let value: FirebaseSourceValue
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            guard c.allKeys.count == 1, let key = c.allKeys.first else { throw Failure.value }
            switch key.stringValue {
            case "nullValue":
                guard try c.decodeNil(forKey: key) else { throw Failure.value }
                value = .null
            case "booleanValue": value = .bool(try c.decode(Bool.self, forKey: key))
            case "stringValue": value = .string(try c.decode(String.self, forKey: key))
            case "integerValue": value = .integer(try c.decode(String.self, forKey: key))
            case "doubleValue":
                value = .double(bits: String(format: "%016llx", try c.decode(Double.self, forKey: key).bitPattern))
            case "bytesValue": value = .bytes(base64: try c.decode(String.self, forKey: key))
            case "referenceValue":
                let reference = try c.decode(String.self, forKey: key)
                guard let prefix = decoder.userInfo[CodingUserInfoKey(rawValue: "sourcePrefix")!] as? String,
                      reference.hasPrefix(prefix) else { throw Failure.scope }
                value = .reference(segments: String(reference.dropFirst(prefix.count)).components(separatedBy: "/"))
            case "timestampValue":
                let raw = try c.decode(String.self, forKey: key)
                guard raw.hasSuffix("Z") else { throw Failure.timestamp }
                let parts = raw.dropLast().split(separator: ".", omittingEmptySubsequences: false)
                guard parts.count <= 2 else { throw Failure.timestamp }
                let fraction = parts.count == 2 ? String(parts[1]) : ""
                guard fraction.count <= 9, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw Failure.timestamp }
                let formatter = ISO8601DateFormatter()
                guard let date = formatter.date(from: String(parts[0]) + "Z") else { throw Failure.timestamp }
                value = .timestamp(seconds: String(Int64(date.timeIntervalSince1970)),
                    nanoseconds: Int(fraction.padding(toLength: 9, withPad: "0", startingAt: 0)) ?? 0)
            case "geoPointValue":
                let point = try c.decode(Coordinates.self, forKey: key)
                value = .geoPoint(latitudeBits: String(format: "%016llx", point.latitude.bitPattern),
                    longitudeBits: String(format: "%016llx", point.longitude.bitPattern))
            case "arrayValue": value = .array(try c.decode(Values.self, forKey: key).values?.map(\.value) ?? [])
            case "mapValue":
                let fields = try c.decode(Fields.self, forKey: key).fields ?? [:]
                value = .map(fields.keys.sorted().map { .init(key: $0, value: fields[$0]!.value) })
            default: throw Failure.value
            }
        }
    }
}
