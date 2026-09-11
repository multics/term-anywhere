import Foundation

public struct TerminalPreferences: Codable, Equatable, Sendable {
    public var fontSize: Double = 14
    public var optionAsMeta = true
    public init() {}
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
    public var revision: String
    public init(_ value: Value, modified: Date = Date(), revision: String = UUID().uuidString) {
        self.value = value; self.modified = modified; self.revision = revision
    }
    public func isNewer(than other: Self) -> Bool {
        modified == other.modified ? revision > other.revision : modified > other.modified
    }
}

public struct SyncedConfiguration: Codable, Equatable, Sendable {
    public static let hostPrefix = "v1.host."
    public static let preferencesKey = "v1.preferences"
    public var hosts: [String: ConfigurationRecord<Host>] = [:]
    public var preferences: ConfigurationRecord<TerminalPreferences>?
    public init() {}
    public var sortedHosts: [Host] { hosts.values.map(\.value).sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name } }
    public mutating func save(_ host: Host, modified: Date = Date()) throws {
        try host.validate()
        let key = Self.hostPrefix + host.id.uuidString
        guard hosts[key]?.value != host else { return }
        let next = max(modified, (hosts[key]?.modified ?? .distantPast).addingTimeInterval(0.001))
        hosts[key] = ConfigurationRecord(host, modified: next)
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
            if hosts[key].map({ record.isNewer(than: $0) }) ?? true { hosts[key] = record }
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
        return result
    }
}
