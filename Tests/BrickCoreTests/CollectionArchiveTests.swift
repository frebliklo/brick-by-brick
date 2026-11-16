import Foundation
import Testing
@testable import BrickCore

struct CollectionArchiveTests {
    private func build(_ id: String = "123-1", count: Int = 3) -> SavedBuild {
        var build = SavedBuild(set: LEGOSet(setNum: id, name: "Test set", year: 2026, numParts: 32, setImgUrl: nil),
                               parts: SampleCatalog.parts, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
        build.setCount(count, for: build.parts[0])
        return build
    }

    @Test func snapshotRoundTripsInventoriesAndProgressWithoutCredentials() throws {
        let source = build()
        let data = try CollectionArchive(builds: [source]).encoded()
        let restored = try #require(CollectionArchive.decode(data).builds.first)
        #expect(restored.set == source.set)
        #expect(restored.parts == source.parts)
        #expect(restored.found == source.found)
        #expect(restored.addedAt == source.addedAt)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["format", "version", "exportedAt", "builds"])
    }

    @Test func keepingExistingProgressAddsOnlyNewSetsAndIsIdempotent() {
        let existing = build(count: 7)
        let unrelated = build("456-1")
        let archive = CollectionArchive(builds: [build(count: 2), build("789-1")])
        let merged = archive.merging(into: [existing, unrelated], existingSets: .keep)
        #expect(merged.map(\.id) == ["789-1", "123-1", "456-1"])
        #expect(merged[1].foundCount == 7)
        #expect(archive.merging(into: merged, existingSets: .keep).count == 3)
    }

    @Test func replacingHonorsLowerCountsAndResetsWithoutRemovingUnrelatedSets() {
        let archive = CollectionArchive(builds: [build(count: 0)])
        let merged = archive.merging(into: [build(count: 7), build("456-1")], existingSets: .replace)
        #expect(merged.count == 2)
        #expect(merged[0].foundCount == 0)
        #expect(merged[1].id == "456-1")
        #expect(merged[1].foundCount == 3)
    }

    @Test func importingRealSetsRetiresPracticeSet() {
        let practice = SavedBuild(set: SampleCatalog.set, parts: SampleCatalog.parts, addedAt: .now)
        let archive = CollectionArchive(builds: [build()])
        #expect(archive.merging(into: [practice], existingSets: .keep).map(\.id) == ["123-1"])
        #expect(CollectionArchive(builds: [practice]).merging(into: [build()], existingSets: .keep).count == 1)
    }

    @Test func malformedAndFutureFilesFailBeforeChangingSavedData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LibraryRepository(fileURL: directory.appendingPathComponent("collection.json"))
        try repository.save([build(count: 7)])
        let before = try Data(contentsOf: repository.fileURL)
        #expect(throws: ArchiveError.self) { try CollectionArchive.decode(Data("broken".utf8)) }
        #expect(throws: ArchiveError.self) {
            try CollectionArchive.decode(Data(#"{"format":"BrickByBrick.collection","version":99}"#.utf8))
        }
        #expect(try Data(contentsOf: repository.fileURL) == before)
    }

    @Test func rejectsDuplicateSetsPartsAndOutOfRangeCounts() throws {
        #expect(throws: ArchiveError.self) { try CollectionArchive(builds: [build(), build()]).encoded() }
        var invalid = build()
        invalid.found["1"] = Int.max
        #expect(throws: ArchiveError.self) { try CollectionArchive(builds: [invalid]).encoded() }
        invalid.found = ["unknown": 1]
        #expect(throws: ArchiveError.self) { try CollectionArchive(builds: [invalid]).encoded() }
        let duplicate = SavedBuild(set: invalid.set, parts: [SampleCatalog.parts[0], SampleCatalog.parts[0]], addedAt: .now)
        #expect(throws: ArchiveError.self) { try CollectionArchive(builds: [duplicate]).encoded() }
        let badPart = InventoryPart(id: 1, part: SampleCatalog.parts[0].part, color: SampleCatalog.parts[0].color,
                                    quantity: Int.max, isSpare: false, elementId: nil)
        let overflow = SavedBuild(set: invalid.set, parts: [badPart], addedAt: .now)
        #expect(throws: ArchiveError.self) { try CollectionArchive(builds: [overflow]).encoded() }
    }

    @Test func rejectsExternalImageTrackingURLs() {
        let set = LEGOSet(setNum: "123-1", name: "Test", year: 2026, numParts: 32,
                          setImgUrl: URL(string: "https://example.com/track"))
        let snapshot = CollectionArchive(builds: [SavedBuild(set: set, parts: SampleCatalog.parts, addedAt: .now)])
        #expect(throws: ArchiveError.self) { try snapshot.encoded() }
    }

    @Test func fileTransferCanBeReadAndSavedLocally() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("collection.brickbybrick")
        try CollectionArchive(builds: [build(count: 6)]).encoded().write(to: file)
        let archive = try CollectionArchive.read(from: file)
        let repository = LibraryRepository(fileURL: directory.appendingPathComponent("collection.json"))
        try repository.save(archive.merging(into: [], existingSets: .keep))
        #expect(try repository.load().first?.foundCount == 6)
    }

    @Test func oversizedFilesAreRejected() {
        #expect(throws: ArchiveError.self) {
            try CollectionArchive.decode(Data(repeating: 32, count: CollectionArchive.maximumBytes + 1))
        }
    }
}
