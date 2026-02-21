import Foundation

// MARK: - Models

struct MetArtwork {
    let id: Int
    let title: String
    let artist: String
    let date: String
    let medium: String
    let department: String
    let imageURL: URL
}

// MARK: - API Actor

actor MetAPI {
    static let shared = MetAPI()

    private var cachedIDs: [Int]?
    private let base = "https://collectionapi.metmuseum.org/public/collection/v1"

    func fetchObjectIDs() async throws -> [Int] {
        if let cached = cachedIDs { return cached }
        let url = URL(string: "\(base)/search?isHighlight=true&hasImages=true&q=*")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        let ids = response.objectIDs ?? []
        cachedIDs = ids
        return ids
    }

    func fetchArtwork(id: Int) async throws -> MetArtwork? {
        let url = URL(string: "\(base)/objects/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONDecoder().decode(ObjectResponse.self, from: data)
        let rawURL = obj.primaryImage?.nonEmpty ?? obj.primaryImageSmall?.nonEmpty
        guard let urlString = rawURL, let imageURL = URL(string: urlString) else { return nil }
        return MetArtwork(
            id: id,
            title: obj.title?.nonEmpty ?? "Untitled",
            artist: obj.artistDisplayName?.nonEmpty ?? "",
            date: obj.objectDate?.nonEmpty ?? "",
            medium: obj.medium?.nonEmpty ?? "",
            department: obj.department?.nonEmpty ?? "",
            imageURL: imageURL
        )
    }

    func fetchRandomArtwork() async throws -> MetArtwork? {
        let ids = try await fetchObjectIDs()
        guard !ids.isEmpty else { return nil }
        for _ in 0..<3 {
            guard let id = ids.randomElement() else { continue }
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
    let medium: String?
    let department: String?
}

// MARK: - Helpers

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
