import Foundation
import Security

enum Paths {
    static let supportDir: URL = {
        // DESKTOPBUDDY_HOME lets the self-test run against a throwaway folder.
        let dir = ProcessInfo.processInfo.environment["DESKTOPBUDDY_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DesktopBuddyV2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let config = supportDir.appendingPathComponent("config.json")
    static let inbox = supportDir.appendingPathComponent("inbox.json")
    static let seen = supportDir.appendingPathComponent("seen.json")
    static let snoozed = supportDir.appendingPathComponent("snoozed.json")
}

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Client secrets and refresh tokens live in the macOS Keychain, never in config.json.
///
/// Everything is kept in ONE Keychain item (a small JSON dictionary) that is read once per launch
/// and cached in memory. macOS asks for Keychain access per item and per app signature, so one
/// item means at most one prompt (and none at all once "Always Allow" is chosen for a build).
enum Keychain {
    private static let service = "com.desktopbuddy.v2"
    private static let storeAccount = "store.v3"
    /// Set by `--snapshot` so offscreen rendering never touches the Keychain.
    nonisolated(unsafe) static var disabled = false
    nonisolated(unsafe) private static var cache: [String: String]?
    private static let lock = NSLock()

    static func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[key]
    }

    static func set(_ value: String?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        var store = load()
        if let value, !value.isEmpty { store[key] = value } else { store.removeValue(forKey: key) }
        guard store != cache else { return }
        cache = store
        save(store)
    }

    // MARK: - Storage

    private static func load() -> [String: String] {
        if let cache { return cache }
        guard !disabled else { cache = [:]; return [:] }
        if let data = read(storeAccount),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
            return dict
        }
        // First launch of v3: fold the old one-item-per-secret entries into the single store.
        let migrated = migrateLegacy()
        cache = migrated
        if !migrated.isEmpty { save(migrated) }
        return migrated
    }

    private static func save(_ store: [String: String]) {
        guard !disabled, let data = try? JSONEncoder().encode(store) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: storeAccount,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = "Desktop Buddy sign-ins"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func read(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func migrateLegacy() -> [String: String] {
        // Listing attributes needs no permission; only reading each secret does (one time).
        let list: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(list as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [:] }
        var dict: [String: String] = [:]
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String, account != storeAccount,
                  let data = read(account), let value = String(data: data, encoding: .utf8) else { continue }
            dict[account] = value
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: service,
                           kSecAttrAccount as String: account] as CFDictionary)
        }
        return dict
    }
}
