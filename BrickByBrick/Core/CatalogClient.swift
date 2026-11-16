import Foundation

struct CatalogPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let count: Int
    let next: URL?
    let results: [Item]
}

enum CatalogError: LocalizedError {
    case missingKey, invalidKey, rateLimited, unavailable, invalidResponse, unsafeURL, emptyInventory
    case invalidLogin, signedOut
    /// 400/404: mapped to a user-facing error by the calling endpoint.
    case badRequest
    var errorDescription: String? {
        switch self {
        case .missingKey: Localization.string("Connect Rebrickable in Settings to search the LEGO catalog.")
        case .invalidKey: Localization.string("Rebrickable didn’t accept this API key. Check it in Settings and try again.")
        case .rateLimited: Localization.string("Rebrickable is receiving too many requests. Wait a moment, then try again.")
        case .unavailable: Localization.string("The catalog is temporarily unavailable. Please try again.")
        case .invalidResponse: Localization.string("The catalog returned an unreadable response. Please try again.")
        case .unsafeURL: Localization.string("The catalog returned an unexpected page address.")
        case .emptyInventory: Localization.string("This set doesn’t have a parts inventory available yet.")
        case .invalidLogin: Localization.string("Rebrickable didn’t accept that username or password.")
        case .signedOut: Localization.string("Your Rebrickable sign-in has expired. Sign in again in Settings.")
        case .badRequest: Localization.string("The catalog returned an unreadable response. Please try again.")
        }
    }
}

/// One entry in a Rebrickable user's own set collection (`/users/{token}/sets/`).
struct OwnedSet: Decodable, Hashable, Identifiable, Sendable {
    let quantity: Int
    let set: LEGOSet
    var id: String { self.set.id }
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

    /// Exchanges a Rebrickable username/email and password for a long-lived user token.
    /// The password is sent once, in the POST body, and never stored.
    func signIn(username: String, password: String) async throws -> String {
        struct TokenResponse: Decodable { let userToken: String }
        // Strict form encoding: only unreserved characters pass, so "&", "+" and "=" in a password survive.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
        let body = "username=\(encode(username.trimmingCharacters(in: .whitespacesAndNewlines)))&password=\(encode(password))"
        let url = URL(string: "https://rebrickable.com/api/v3/users/_token/")!
        do {
            let response: TokenResponse = try await fetch(url, method: "POST", body: Data(body.utf8))
            return response.userToken
        } catch CatalogError.badRequest, CatalogError.invalidKey {
            // The API key was verified when connecting, so a rejection here means the login was wrong.
            throw CatalogError.invalidLogin
        }
    }

    /// Every set in the signed-in user's Rebrickable collection, across all set lists.
    func ownedSets(userToken: String) async throws -> [OwnedSet] {
        let url = URL(string: "https://rebrickable.com/api/v3/users/")!
            .appendingPathComponent(userToken).appendingPathComponent("sets")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path += "/"
        components.queryItems = [URLQueryItem(name: "page_size", value: "1000")]
        var sets: [String: OwnedSet] = [:]
        do {
            for try await entry in pages(of: OwnedSet.self, from: components.url!) {
                // The same set can appear in several set lists; merge them.
                if let existing = sets[entry.id] {
                    sets[entry.id] = OwnedSet(quantity: existing.quantity + entry.quantity, set: entry.set)
                } else { sets[entry.id] = entry }
            }
        } catch CatalogError.badRequest {
            // Rebrickable answers 404 for an unknown or revoked user token.
            throw CatalogError.signedOut
        }
        return sets.values.sorted { $0.set.name.localizedStandardCompare($1.set.name) == .orderedAscending }
    }

    func inventory(for set: LEGOSet) async throws -> [InventoryPart] {
        let url = URL(string: "https://rebrickable.com/api/v3/lego/sets/")!
            .appendingPathComponent(set.setNum).appendingPathComponent("parts")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path += "/"
        components.queryItems = [URLQueryItem(name: "page_size", value: "1000"),
                                 URLQueryItem(name: "inc_minifig_parts", value: "1")]
        var parts: [Int: InventoryPart] = [:]
        for try await part in pages(of: InventoryPart.self, from: components.url!) where part.quantity > 0 {
            parts[part.id] = part
        }
        guard !parts.isEmpty else { throw CatalogError.emptyInventory }
        return parts.values.sorted {
            if $0.color.name != $1.color.name { return $0.color.name < $1.color.name }
            if $0.part.name != $1.part.name { return $0.part.name < $1.part.name }
            return $0.id < $1.id
        }
    }

    /// Follows `next` links until the last page, refusing cycles.
    private func pages<Item: Decodable & Sendable>(of _: Item.Type, from first: URL) -> AsyncThrowingStream<Item, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var next: URL? = first
                    var visited = Set<URL>()
                    while let pageURL = next {
                        try Task.checkCancellation()
                        guard visited.insert(pageURL).inserted else { throw CatalogError.invalidResponse }
                        let page: CatalogPage<Item> = try await fetch(pageURL)
                        for item in page.results { continuation.yield(item) }
                        next = page.next
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func fetch<T: Decodable & Sendable>(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> T {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CatalogError.missingKey }
        // Never forward the user's credential to a pagination URL on another host.
        guard url.scheme == "https", url.host == "rebrickable.com", url.port == nil,
              url.user == nil, url.password == nil, url.path.hasPrefix("/api/v3/") else {
            throw CatalogError.unsafeURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 200...299: break
        case 400, 404: throw CatalogError.badRequest
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
