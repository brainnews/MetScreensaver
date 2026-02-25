import Foundation

// MARK: - Models

struct MetArtwork {
    let id: Int
    let title: String
    let artist: String
    let date: String
    let department: String
    let imageURL: URL
}

// MARK: - API Actor

actor MetAPI {
    static let shared = MetAPI()

    private var cachedIDs: [Int]?
    private let base = "https://collectionapi.metmuseum.org/public/collection/v1"

    // Shorter timeouts to fail fast rather than hanging for 60 s
    private let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    // UserDefaults keys for persisting the ID list across screensaver launches
    private static let cacheIDsKey  = "MetAPI.objectIDs"
    private static let cacheDateKey = "MetAPI.objectIDsDate"
    private static let cacheTTL: TimeInterval = 24 * 60 * 60  // 24 hours

    func fetchObjectIDs() async throws -> [Int] {
        if let cached = cachedIDs { return cached }

        // Check UserDefaults — avoids the slow search request on every launch
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: Self.cacheIDsKey) as? [Int],
           let date  = defaults.object(forKey: Self.cacheDateKey) as? Date,
           Date().timeIntervalSince(date) < Self.cacheTTL {
            cachedIDs = saved
            return saved
        }

        let url = URL(string: "\(base)/search?isHighlight=true&hasImages=true&q=*")!
        let (data, _) = try await urlSession.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        let ids = response.objectIDs ?? []
        cachedIDs = ids
        defaults.set(ids,    forKey: Self.cacheIDsKey)
        defaults.set(Date(), forKey: Self.cacheDateKey)
        return ids
    }

    func fetchArtwork(id: Int) async throws -> MetArtwork? {
        let url = URL(string: "\(base)/objects/\(id)")!
        let (data, _) = try await urlSession.data(from: url)
        let obj = try JSONDecoder().decode(ObjectResponse.self, from: data)
        let rawURL = obj.primaryImage?.nonEmpty ?? obj.primaryImageSmall?.nonEmpty
        guard let urlString = rawURL, let imageURL = URL(string: urlString) else { return nil }
        return MetArtwork(
            id: id,
            title: obj.title?.nonEmpty ?? "Untitled",
            artist: obj.artistDisplayName?.nonEmpty ?? "",
            date: obj.objectDate?.nonEmpty ?? "",
            department: obj.department?.nonEmpty ?? "",
            imageURL: imageURL
        )
    }

    func fetchRandomArtwork() async throws -> MetArtwork? {
        let ids = try await fetchObjectIDs()
        guard !ids.isEmpty else { return nil }
        // Shuffle a small prefix so each retry uses a distinct ID
        for id in ids.shuffled().prefix(3) {
            if let artwork = try? await fetchArtwork(id: id) { return artwork }
        }
        return nil
    }
}

// MARK: - Private Decodable Types

private struct SearchResponse: Decodable {
    let objectIDs: [Int]?
}

private struct ObjectResponse: Decodable {
    let primaryImage: String?
    let primaryImageSmall: String?
    let title: String?
    let artistDisplayName: String?
    let objectDate: String?
    let department: String?
}

// MARK: - Helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
