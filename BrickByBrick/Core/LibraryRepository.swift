import Foundation

struct LibraryRepository {
    let fileURL: URL

    func load() throws -> [SavedBuild] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([SavedBuild].self, from: Data(contentsOf: fileURL))
    }

    func save(_ builds: [SavedBuild]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(builds).write(to: fileURL, options: .atomic)
    }
}
