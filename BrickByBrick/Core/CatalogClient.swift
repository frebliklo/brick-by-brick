import Foundation

struct CatalogPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let count: Int
    let next: URL?
    let results: [Item]
}

enum CatalogError: LocalizedError {
    case missingKey, invalidKey, rateLimited, unavailable, invalidResponse, unsafeURL, emptyInventory
    var errorDescription: String? {
        switch self {
        case .missingKey: Localization.string("Connect Rebrickable in Settings to search the LEGO catalog.")
        case .invalidKey: Localization.string("Rebrickable didn’t accept this API key. Check it in Settings and try again.")
        case .rateLimited: Localization.string("Rebrickable is receiving too many requests. Wait a moment, then try again.")
        case .unavailable: Localization.string("The catalog is temporarily unavailable. Please try again.")
        case .invalidResponse: Localization.string("The catalog returned an unreadable response. Please try again.")
        case .unsafeURL: Localization.string("The catalog returned an unexpected page address.")
        case .emptyInventory: Localization.string("This set doesn’t have a parts inventory available yet.")
        }
    }
}

struct CatalogClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    let apiKey: String
    var transport: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        return (data, response)
    }

    func search(_ query: String, next: URL? = nil) async throws -> CatalogPage<LEGOSet> {
        var components = URLComponents(string: "https://rebrickable.com/api/v3/lego/sets/")!
        components.queryItems = [URLQueryItem(name: "search", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
                                 URLQueryItem(name: "page_size", value: "40")]
        return try await fetch(next ?? components.url!)
    }

    func inventory(for set: LEGOSet) async throws -> [InventoryPart] {
        let url = URL(string: "https://rebrickable.com/api/v3/lego/sets/")!
            .appendingPathComponent(set.setNum).appendingPathComponent("parts")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path += "/"
        components.queryItems = [URLQueryItem(name: "page_size", value: "1000"),
                                 URLQueryItem(name: "inc_minifig_parts", value: "1")]
        var next: URL? = components.url
        var visited = Set<URL>()
        var parts: [Int: InventoryPart] = [:]
        while let pageURL = next {
            try Task.checkCancellation()
            guard visited.insert(pageURL).inserted else { throw CatalogError.invalidResponse }
            let page: CatalogPage<InventoryPart> = try await fetch(pageURL)
            for part in page.results where part.quantity > 0 { parts[part.id] = part }
            next = page.next
        }
        guard !parts.isEmpty else { throw CatalogError.emptyInventory }
        return parts.values.sorted {
            if $0.color.name != $1.color.name { return $0.color.name < $1.color.name }
            if $0.part.name != $1.part.name { return $0.part.name < $1.part.name }
            return $0.id < $1.id
        }
    }

    private func fetch<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CatalogError.missingKey }
        // Never forward the user's credential to a pagination URL on another host.
        guard url.scheme == "https", url.host == "rebrickable.com", url.port == nil,
              url.user == nil, url.password == nil, url.path.hasPrefix("/api/v3/") else {
            throw CatalogError.unsafeURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw CatalogError.invalidKey
        case 429: throw CatalogError.rateLimited
        default: throw CatalogError.unavailable
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw CatalogError.invalidResponse }
    }
}
