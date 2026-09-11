import Foundation

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    public var title: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
}

public struct TerminalPreferences: Codable, Equatable, Sendable {
    public var fontSize: Double = 14
    public var optionAsMeta = true
    public var appearance: AppAppearance = .system
    public init() {}
    private enum CodingKeys: String, CodingKey { case fontSize, optionAsMeta, appearance }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try values.decode(Double.self, forKey: .fontSize)
        optionAsMeta = try values.decode(Bool.self, forKey: .optionAsMeta)
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
    }
    public func validate() throws {
        guard fontSize.isFinite, (10...28).contains(fontSize) else {
            throw ConnectionError.message("Terminal text size must be between 10 and 28 points.")
        }
    }
}

/// Each host has its own iCloud key, so edits to different hosts do not overwrite one another.
public struct ConfigurationRecord<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var value: Value
    public var modified: Date
    public var deleted: Bool?
    public var revision: String
    public init(_ value: Value, modified: Date = Date(), revision: String = UUID().uuidString, deleted: Bool = false) {
        self.value = value; self.modified = modified; self.revision = revision; self.deleted = deleted ? true : nil
    }
    public func isNewer(than other: Self) -> Bool {
        modified == other.modified ? revision > other.revision : modified > other.modified
    }
}

public struct SyncedConfiguration: Codable, Equatable, Sendable {
    public static let hostPrefix = "v1.host."
    public static let preferencesKey = "v1.preferences"
    public static let hostOrderKey = "v1.hostOrder"
    public var hosts: [String: ConfigurationRecord<Host>] = [:]
    public var preferences: ConfigurationRecord<TerminalPreferences>?
    public var hostOrder: ConfigurationRecord<[UUID]>?
    public init() {}
    public var sortedHosts: [Host] {
        let visible: [Host] = hosts.values.compactMap { record in record.deleted == true ? nil : record.value }
        let alphabetical = visible.sorted { a, b in
            if a.name == b.name { return a.id.uuidString < b.id.uuidString }
            return a.name < b.name
        }
        guard let order = hostOrder?.value else { return alphabetical }
        let byID: [UUID: Host] = Dictionary(uniqueKeysWithValues: alphabetical.map { ($0.id, $0) })
        let ordered = Set(order)
        return order.compactMap { byID[$0] } + alphabetical.filter { !ordered.contains($0.id) }
    }
    public mutating func saveHostOrder(_ ids: [UUID], modified: Date = Date()) throws {
        guard ids.count <= 1000, Set(ids).count == ids.count else { throw ConnectionError.message("The host order is invalid.") }
        guard hostOrder?.value != ids else { return }
        let next = max(modified, (hostOrder?.modified ?? .distantPast).addingTimeInterval(0.001))
        hostOrder = ConfigurationRecord(ids, modified: next)
    }
    public mutating func save(_ host: Host, modified: Date = Date()) throws {
        try host.validate()
        let key = Self.hostPrefix + host.id.uuidString
        guard hosts[key]?.deleted != true else { throw ConnectionError.message("This host was removed on another device. Add it again as a new host to restore it.") }
        guard hosts[key]?.value != host else { return }
        let next = max(modified, (hosts[key]?.modified ?? .distantPast).addingTimeInterval(0.001))
        hosts[key] = ConfigurationRecord(host, modified: next)
    }
    public mutating func removeHost(id: UUID, modified: Date = Date()) {
        let key = Self.hostPrefix + id.uuidString
        guard let existing = hosts[key], existing.deleted != true else { return }
        let next = max(modified, existing.modified.addingTimeInterval(0.001))
        hosts[key] = ConfigurationRecord(existing.value, modified: next, deleted: true)
    }
    public mutating func save(_ value: TerminalPreferences, modified: Date = Date()) throws {
        try value.validate()
        guard preferences?.value != value else { return }
        let next = max(modified, (preferences?.modified ?? .distantPast).addingTimeInterval(0.001))
        preferences = ConfigurationRecord(value, modified: next)
    }
    public mutating func merge(key: String, data: Data) throws {
        if key.hasPrefix(Self.hostPrefix) {
            let record = try JSONDecoder().decode(ConfigurationRecord<Host>.self, from: data)
            try record.value.validate()
            guard key == Self.hostPrefix + record.value.id.uuidString else { throw ConnectionError.message("An iCloud host has an invalid identifier.") }
            // Removal wins over edits to the same ID, including edits made while offline.
            if let current = hosts[key] {
                if current.deleted == true && record.deleted != true { return }
                if record.deleted == true && current.deleted != true { hosts[key] = record; return }
            }
            if hosts[key].map({ record.isNewer(than: $0) }) ?? true { hosts[key] = record }
        } else if key == Self.hostOrderKey {
            let record = try JSONDecoder().decode(ConfigurationRecord<[UUID]>.self, from: data)
            guard record.value.count <= 1000, Set(record.value).count == record.value.count else { throw ConnectionError.message("The iCloud host order is invalid.") }
            if hostOrder.map({ record.isNewer(than: $0) }) ?? true { hostOrder = record }
        } else if key == Self.preferencesKey {
            let record = try JSONDecoder().decode(ConfigurationRecord<TerminalPreferences>.self, from: data)
            try record.value.validate()
            if preferences.map({ record.isNewer(than: $0) }) ?? true { preferences = record }
        }
    }
    public func encodedRecords() throws -> [String: Data] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var result = try hosts.mapValues { try encoder.encode($0) }
        if let preferences { result[Self.preferencesKey] = try encoder.encode(preferences) }
        if let hostOrder { result[Self.hostOrderKey] = try encoder.encode(hostOrder) }
        return result
    }
}
