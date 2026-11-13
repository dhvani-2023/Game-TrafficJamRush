import Foundation

/// Typed key-value store over `UserDefaults` that keeps Android's key names and value encodings,
/// so saves port 1:1 (Base64 bitsets, digit strings, CSV lists, JSON strings).
public final class Prefs: @unchecked Sendable {
    public let defaults: UserDefaults
    private let prefix: String

    /// `name` mirrors the Android preferences file name; keys are stored as "<name>.<key>".
    public init(name: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prefix = name.isEmpty ? "" : name + "."
    }

    private func k(_ key: String) -> String { prefix + key }

    public func contains(_ key: String) -> Bool { defaults.object(forKey: k(key)) != nil }

    public func int(_ key: String, _ def: Int = 0) -> Int {
        (defaults.object(forKey: k(key)) as? NSNumber)?.intValue ?? def
    }

    public func long(_ key: String, _ def: Int64 = 0) -> Int64 {
        (defaults.object(forKey: k(key)) as? NSNumber)?.int64Value ?? def
    }

    public func float(_ key: String, _ def: Float = 0) -> Float {
        (defaults.object(forKey: k(key)) as? NSNumber)?.floatValue ?? def
    }

    public func double(_ key: String, _ def: Double = 0) -> Double {
        (defaults.object(forKey: k(key)) as? NSNumber)?.doubleValue ?? def
    }

    public func bool(_ key: String, _ def: Bool = false) -> Bool {
        (defaults.object(forKey: k(key)) as? NSNumber)?.boolValue ?? def
    }

    public func string(_ key: String, _ def: String = "") -> String {
        defaults.string(forKey: k(key)) ?? def
    }

    public func optionalString(_ key: String) -> String? { defaults.string(forKey: k(key)) }

    public func stringSet(_ key: String, _ def: Set<String> = []) -> Set<String> {
        (defaults.array(forKey: k(key)) as? [String]).map(Set.init) ?? def
    }

    public func set(_ key: String, _ v: Int) { defaults.set(v, forKey: k(key)) }
    public func set(_ key: String, _ v: Int64) { defaults.set(NSNumber(value: v), forKey: k(key)) }
    public func set(_ key: String, _ v: Float) { defaults.set(v, forKey: k(key)) }
    public func set(_ key: String, _ v: Double) { defaults.set(v, forKey: k(key)) }
    public func set(_ key: String, _ v: Bool) { defaults.set(v, forKey: k(key)) }
    public func set(_ key: String, _ v: String) { defaults.set(v, forKey: k(key)) }
    public func set(_ key: String, _ v: Set<String>) { defaults.set(Array(v).sorted(), forKey: k(key)) }
    public func remove(_ key: String) { defaults.removeObject(forKey: k(key)) }

    /// Codable value stored as a JSON string (like kotlinx.serialization strings in SharedPreferences).
    public func codable<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let s = defaults.string(forKey: k(key)), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    public func setCodable<T: Encodable>(_ key: String, _ value: T) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(value), let s = String(data: d, encoding: .utf8) {
            defaults.set(s, forKey: k(key))
        }
    }

    /// Removes every key that belongs to this store.
    public func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// JSON files in Application Support (saved games, profiles).
public enum FileStore {
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    public static func write<T: Encodable>(_ value: T, to name: String) {
        let enc = JSONEncoder()
        if let d = try? enc.encode(value) { try? d.write(to: url(name), options: .atomic) }
    }

    public static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let d = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    public static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    public static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(name).path) }
}

/// Day maths in the device's local calendar (streaks, daily rewards, rentals).
public enum Days {
    /// Days since 1970-01-01 in local time (like Android's `LocalDate.now().toEpochDay()`).
    public static func epochDay(_ date: Date = Date()) -> Int {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let d = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
        return Int((d.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// yyyyMMdd as an Int (daily seeds).
    public static func yyyymmdd(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 1970) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    public static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
