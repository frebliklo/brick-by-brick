import Foundation

/// A portable snapshot, deliberately separate from credentials and device preferences.
struct CollectionArchive: Codable, Sendable, Identifiable {
    static let maximumBytes = 25 * 1_024 * 1_024
    let format: String
    let version: Int
    let exportedAt: Date
    let builds: [SavedBuild]
    var id: Date { exportedAt }

    init(builds: [SavedBuild], exportedAt: Date = .now) {
        format = "BrickByBrick.collection"
        version = 1
        self.exportedAt = exportedAt
        self.builds = builds
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ArchiveError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ArchiveError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Read the version first so a newer schema produces a useful error.
        struct Header: Decodable { let format: String; let version: Int }
        guard let header = try? decoder.decode(Header.self, from: data),
              header.format == "BrickByBrick.collection" else { throw ArchiveError.invalid }
        guard header.version == 1 else { throw ArchiveError.unsupportedVersion }
        guard let archive = try? decoder.decode(Self.self, from: data) else { throw ArchiveError.invalid }
        try archive.validate()
        return archive
    }

    static func read(from url: URL) throws -> Self {
        guard url.isFileURL else { throw ArchiveError.invalid }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Self, Error> = .failure(ArchiveError.invalid)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let file = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? file.close() }
                let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
                return try decode(data)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    enum ExistingSets: String, CaseIterable { case keep, replace }

    /// Never remove unrelated sets or combine counters (which could double-count bricks).
    func merging(into current: [SavedBuild], existingSets: ExistingSets) -> [SavedBuild] {
        let incoming = Dictionary(uniqueKeysWithValues: builds.map { ($0.id, $0) })
        let currentIDs = Set(current.map(\.id))
        let retained = current.map { existingSets == .replace ? incoming[$0.id] ?? $0 : $0 }
        let combined = builds.filter { !currentIDs.contains($0.id) } + retained
        return combined.contains(where: { !$0.set.isSample }) ? combined.filter { !$0.set.isSample } : combined
    }

    private func validate() throws {
        guard format == "BrickByBrick.collection", version == 1,
              builds.count <= 1_000, Set(builds.map(\.id)).count == builds.count else { throw ArchiveError.invalid }
        var partCount = 0
        for build in builds {
            partCount += build.parts.count
            guard !build.id.isEmpty, build.id.count <= 100, build.set.name.count <= 1_000,
                  build.set.numParts >= 0, partCount <= 100_000,
                  Set(build.parts.map(\.id)).count == build.parts.count else { throw ArchiveError.invalid }
            let quantities = Dictionary(uniqueKeysWithValues: build.parts.map { (String($0.id), $0.quantity) })
            guard build.parts.allSatisfy({ (1...100_000).contains($0.quantity) }),
                  build.found.allSatisfy({ key, count in
                      guard let quantity = quantities[key] else { return false }
                      return (0...quantity).contains(count)
                  }) else { throw ArchiveError.invalid }
            // Imported image links must remain catalog links, not arbitrary tracking URLs.
            let imageURLs = [build.set.setImgUrl] + build.parts.map { $0.part.partImgUrl }
            guard imageURLs.allSatisfy({ url in
                guard let url else { return true }
                let host = url.host?.lowercased() ?? ""
                return url.scheme == "https" && url.user == nil && url.password == nil
                    && (host == "rebrickable.com" || host.hasSuffix(".rebrickable.com"))
            }) else { throw ArchiveError.invalid }
        }
    }
}

enum ArchiveError: LocalizedError {
    case invalid, unsupportedVersion, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalid: Localization.string("This file isn’t a valid Brick by Brick collection. Your saved sets haven’t changed.")
        case .unsupportedVersion: Localization.string("This collection was exported by a different file-format version. Update Brick by Brick and try again.")
        case .tooLarge: Localization.string("This collection is too large to transfer. The maximum file size is 25 MB.")
        }
    }
}
