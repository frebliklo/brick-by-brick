import Foundation
import Testing
@testable import BrickCore

/// Hits the real Rebrickable API. Skipped unless REBRICKABLE_API_KEY is set.
struct LiveRebrickableTests {
    private static let key = ProcessInfo.processInfo.environment["REBRICKABLE_API_KEY"] ?? ""

    @Test(.enabled(if: !key.isEmpty, "REBRICKABLE_API_KEY not set"))
    func searchAndInventoryWorkWithRealKey() async throws {
        let client = CatalogClient(apiKey: Self.key)
        let page = try await client.search("31124")
        let set = try #require(page.results.first)
        #expect(set.setNum.hasPrefix("31124"))
        let parts = try await client.inventory(for: set)
        #expect(!parts.isEmpty)
    }

    @Test(.enabled(if: !key.isEmpty, "REBRICKABLE_API_KEY not set"))
    func bogusKeyIsRejected() async {
        let client = CatalogClient(apiKey: "not-a-real-key")
        await #expect(throws: CatalogError.self) { _ = try await client.search("31124") }
    }
}
