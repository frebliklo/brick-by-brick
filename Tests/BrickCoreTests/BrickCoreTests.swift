import Foundation
import Testing
@testable import BrickCore

struct BrickCoreTests {
    @Test func quantitiesAreClampedAndToggleIsReversible() {
        var build = SavedBuild(set: SampleCatalog.set, parts: SampleCatalog.parts, addedAt: .now)
        let part = build.parts[0]
        build.setCount(3, for: part)
        #expect(build.foundCount == 3)
        build.setCount(999, for: part)
        #expect(build.count(for: part) == 8)
        build.toggle(part)
        #expect(build.count(for: part) == 0)
        build.toggle(part)
        #expect(build.count(for: part) == 8)
        build.setCount(-5, for: part)
        #expect(build.foundCount == 0)
        #expect(build.totalCount == 32)
    }

    @Test func samePartInDifferentColorsHasIndependentProgress() {
        var build = SavedBuild(set: SampleCatalog.set, parts: SampleCatalog.parts, addedAt: .now)
        build.setCount(5, for: build.parts[0])
        #expect(build.count(for: build.parts[1]) == 0)
        #expect(build.foundCount == 5)
    }

    @Test func sparesDoNotAffectCompletion() {
        let spare = InventoryPart(id: 100, part: SampleCatalog.parts[0].part, color: SampleCatalog.parts[0].color,
                                  quantity: 2, isSpare: true, elementId: nil)
        var build = SavedBuild(set: SampleCatalog.set, parts: SampleCatalog.parts + [spare], addedAt: .now)
        build.setCount(2, for: spare)
        #expect(build.foundCount == 0)
        for part in build.requiredParts { build.setCount(part.quantity, for: part) }
        #expect(build.isComplete)
        #expect(build.progress == 1)
        #expect(build.totalCount == 32)
    }

    @Test func savedProgressSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LibraryRepository(fileURL: directory.appendingPathComponent("collection.json"))
        #expect(try repository.load().isEmpty)
        var build = SavedBuild(set: SampleCatalog.set, parts: SampleCatalog.parts, addedAt: .now)
        build.setCount(4, for: build.parts[0])
        try repository.save([build])
        let restored = try #require(repository.load().first)
        #expect(restored.foundCount == 4)
        #expect(restored.parts == build.parts)
        try repository.save([])
        #expect(try repository.load().isEmpty)
    }

    @Test func malformedSavedDataIsNotSilentlyReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("broken".utf8).write(to: file)
        #expect(throws: (any Error).self) { try LibraryRepository(fileURL: file).load() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "broken")
    }

    @Test func searchEncodesQueryAndDecodesCatalog() async throws {
        let client = CatalogClient(apiKey: "test-key", transport: { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "key test-key")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            #expect(components.queryItems?.first(where: { $0.name == "search" })?.value == "City & space")
            return Self.response(request, body: """
            {"count":1,"next":null,"results":[{"set_num":"123-1","name":"Test set","year":2024,"num_parts":32,"set_img_url":null}]}
            """)
        })
        let page = try await client.search("  City & space  ")
        #expect(page.results.first?.setNum == "123-1")
        #expect(page.results.first?.numParts == 32)
    }

    @Test func inventoryLoadsEveryPageAndMinifigureParts() async throws {
        let client = CatalogClient(apiKey: "test-key", transport: { request in
            let url = request.url!
            if url.query?.contains("page=2") == true {
                return Self.response(request, body: Self.inventoryJSON(id: 2, next: "null", spare: true))
            }
            #expect(url.path == "/api/v3/lego/sets/123-1/parts")
            #expect(url.query?.contains("inc_minifig_parts=1") == true)
            return Self.response(request, body: Self.inventoryJSON(id: 1, next: "\"https://rebrickable.com/api/v3/lego/sets/123-1/parts/?page=2\"", spare: false))
        })
        let set = LEGOSet(setNum: "123-1", name: "Test", year: 2024, numParts: 2, setImgUrl: nil)
        let parts = try await client.inventory(for: set)
        #expect(parts.count == 2)
        #expect(parts.contains { $0.isSpare })
        #expect(parts[0].part.partNum == "3001")
    }

    @Test func paginationNeverForwardsKeyToAnotherHost() async {
        let client = CatalogClient(apiKey: "test-key", transport: { _ in
            Issue.record("Transport should not be called for an untrusted URL")
            throw CatalogError.invalidResponse
        })
        await #expect(throws: CatalogError.self) {
            try await client.search("x", next: URL(string: "https://example.com/api/v3/lego/sets/")!)
        }
    }

    @Test(arguments: [401, 403, 429, 500])
    func serverFailuresHaveActionableErrors(status: Int) async {
        let client = CatalogClient(apiKey: "test", transport: { request in Self.response(request, body: "{}", status: status) })
        await #expect(throws: CatalogError.self) { try await client.search("x") }
    }

    @Test func paginationCyclesFailInsteadOfLooping() async {
        let client = CatalogClient(apiKey: "test", transport: { request in
            Self.response(request, body: Self.inventoryJSON(id: 1, next: "\"https://rebrickable.com/api/v3/loop/\"", spare: false))
        })
        await #expect(throws: CatalogError.self) { try await client.inventory(for: SampleCatalog.set) }
    }

    @Test func signInPostsFormEncodedCredentialsAndReturnsToken() async throws {
        let client = CatalogClient(apiKey: "test-key", transport: { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://rebrickable.com/api/v3/users/_token/")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "key test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body == "username=brick%40example.com&password=a%2Bb%26c")
            #expect(request.url?.query == nil)
            return Self.response(request, body: #"{"user_token":"abc123"}"#)
        })
        let token = try await client.signIn(username: " brick@example.com ", password: "a+b&c")
        #expect(token == "abc123")
    }

    @Test(arguments: [400, 401])
    func rejectedSignInIsALoginError(status: Int) async {
        let client = CatalogClient(apiKey: "test", transport: { request in Self.response(request, body: "{}", status: status) })
        await #expect(throws: CatalogError.invalidLogin) { try await client.signIn(username: "a", password: "b") }
    }

    @Test func ownedSetsFollowPagesAndMergeDuplicateLists() async throws {
        let client = CatalogClient(apiKey: "test-key", transport: { request in
            let url = request.url!
            let entry = { (num: String, qty: Int) in
                #"{"list_id":1,"quantity":\#(qty),"include_spares":true,"set":{"set_num":"\#(num)","name":"Set \#(num)","year":2024,"num_parts":10,"set_img_url":null,"theme_id":1}}"#
            }
            if url.query?.contains("page=2") == true {
                return Self.response(request, body: #"{"count":3,"next":null,"results":[\#(entry("1-1", 1))]}"#)
            }
            #expect(url.path == "/api/v3/users/tok/sets")
            return Self.response(request, body: #"{"count":3,"next":"https://rebrickable.com/api/v3/users/tok/sets/?page=2","results":[\#(entry("1-1", 1)),\#(entry("2-1", 1))]}"#)
        })
        let sets = try await client.ownedSets(userToken: "tok")
        #expect(sets.map(\.id) == ["1-1", "2-1"])
        #expect(sets.first?.quantity == 2)
    }

    @Test func unknownUserTokenMeansSignedOut() async {
        let client = CatalogClient(apiKey: "test", transport: { request in Self.response(request, body: "{}", status: 404) })
        await #expect(throws: CatalogError.signedOut) { try await client.ownedSets(userToken: "gone") }
    }

    private static func response(_ request: URLRequest, body: String, status: Int = 200) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    private static func inventoryJSON(id: Int, next: String, spare: Bool) -> String {
        """
        {"count":2,"next":\(next),"results":[{"id":\(id),"part":{"part_num":"3001","name":"Brick 2 x 4","part_img_url":null},"color":{"id":4,"name":"Red","rgb":"C91A09"},"quantity":2,"is_spare":\(spare),"element_id":null}]}
        """
    }
}
