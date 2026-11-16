import SwiftUI
import Security

@MainActor @Observable
final class AppStore {
    private(set) var builds: [SavedBuild] = []
    private(set) var apiKey = ""
    var storageError: String?
    private let repository: LibraryRepository
    private var canSave = true
    private static let languageKey = "appLanguage"
    private static let appearanceKey = "appAppearance"

    /// Light, dark, or follow the device; persisted.
    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// The user's language choice; persisted, defaults to the device language.
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            Localization.use(language)
        }
    }
    var locale: Locale { language.locale }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.languageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = saved
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey).flatMap(AppAppearance.init(rawValue:)) ?? .system
        Localization.use(saved)
        var root = URL.applicationSupportDirectory.appendingPathComponent("BrickByBrick")
        var isUITesting = false
        #if DEBUG
        isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        if isUITesting {
            root = root.appendingPathComponent("UITests")
        }
        #endif
        repository = LibraryRepository(fileURL: root.appendingPathComponent("collection.json"))
        do { builds = try repository.load() }
        catch {
            canSave = false
            storageError = Localization.string("Your saved collection couldn’t be read. The original file has been preserved. \(error.localizedDescription)")
        }
        apiKey = isUITesting ? "" : (Keychain.read() ?? "")
        // The practice set is only for trying the app before adding a real set.
        if builds.contains(where: { !$0.set.isSample }), builds.contains(where: { $0.set.isSample }) {
            _ = commit(builds.filter { !$0.set.isSample })
        }
    }

    var isConnected: Bool { !apiKey.isEmpty }
    var client: CatalogClient { CatalogClient(apiKey: apiKey) }

    func saveKey(_ value: String) throws {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try Keychain.write(cleaned)
        apiKey = cleaned
    }

    func build(_ id: String) -> SavedBuild? { builds.first { $0.id == id } }

    @discardableResult
    func add(_ set: LEGOSet, parts: [InventoryPart]) -> Bool {
        guard build(set.id) == nil else { return true }
        // Adding a real set retires the practice set and its progress.
        let kept = set.isSample ? builds : builds.filter { !$0.set.isSample }
        return commit([SavedBuild(set: set, parts: parts, addedAt: .now)] + kept)
    }

    func update(_ id: String, part: InventoryPart, count: Int) {
        var updated = builds
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].setCount(count, for: part)
        _ = commit(updated)
    }

    func reset(_ id: String) {
        var updated = builds
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].found = [:]
        _ = commit(updated)
    }

    func remove(_ id: String) { _ = commit(builds.filter { $0.id != id }) }

    @discardableResult
    func importCollection(_ archive: CollectionArchive, existingSets: CollectionArchive.ExistingSets) -> Bool {
        commit(archive.merging(into: builds, existingSets: existingSets))
    }

    private func commit(_ updated: [SavedBuild]) -> Bool {
        guard canSave else {
            storageError = Localization.string("Saving is paused because your collection file couldn’t be read. Relaunch after restoring the file.")
            return false
        }
        do {
            try repository.save(updated)
            builds = updated
            return true
        } catch {
            storageError = Localization.string("Your change couldn’t be saved. Please try again. \(error.localizedDescription)")
            return false
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Keychain {
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.brickbybrick.catalog",
         kSecAttrAccount as String: "rebrickable-api-key"]
    }
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.failed }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.failed }
    }
    enum KeychainError: LocalizedError {
        case failed
        var errorDescription: String? { Localization.string("The API key couldn’t be saved securely. Please try again.") }
    }
}
