//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// A tiny read-only GitHub REST client for issue import. Off-main-actor, value-typed, and free of
/// any third-party dependency — it exists only to fetch what the importer maps into tasks.
nonisolated struct GitHubClient: Sendable {

    private let token: String
    private let session: URLSession
    private let baseURL = URL(string: "https://api.github.com")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Endpoints

    /// Verifies the token by fetching the authenticated user; returns the login on success.
    func verify() async throws -> String {
        let user: GitHubUser = try await get(path: "/user")
        return user.login
    }

    /// Fetches every issue (open and closed) for `owner/repo`, following pagination. Pull requests —
    /// which the issues endpoint interleaves — are filtered out.
    func issues(owner: String, repo: String) async throws -> [GitHubIssue] {
        var result: [GitHubIssue] = []
        var url: URL? = makeURL(
            path: "/repos/\(owner)/\(repo)/issues",
            query: [("state", "all"), ("per_page", "100")]
        )
        while let next = url {
            let (page, nextURL): ([GitHubIssue], URL?) = try await getPage(url: next)
            result.append(contentsOf: page.filter { $0.pullRequest == nil })
            url = nextURL
        }
        return result
    }

    // MARK: - Repository URL parsing

    /// Extracts `(owner, repo)` from a GitHub repository URL such as
    /// `https://github.com/owner/repo` or `git@github.com:owner/repo.git`.
    static func parseRepo(from urlString: String) -> (owner: String, repo: String)? {
        var string = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        // Normalise the scp-style git remote to a path we can split.
        if let range = string.range(of: "github.com") {
            string = String(string[range.upperBound...])
        } else {
            return nil
        }
        // Drop a leading ":" (scp form) or "/" (https path), then trailing ".git" and slashes.
        string = string.trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        if string.hasSuffix(".git") { string.removeLast(4) }
        let parts = string.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    // MARK: - Request plumbing

    private func makeURL(path: String, query: [(String, String)]) -> URL? {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components?.url
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Flowplan", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Decodes a single JSON body from `path`.
    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = makeURL(path: path, query: []) else { throw GitHubError.badRepositoryURL }
        let (data, response) = try await session.data(for: makeRequest(url: url))
        try Self.validate(response)
        return try Self.decoder.decode(T.self, from: data)
    }

    /// Decodes one page and returns the parsed `Link: rel="next"` URL, if any.
    private func getPage<T: Decodable>(url: URL) async throws -> (T, URL?) {
        let (data, response) = try await session.data(for: makeRequest(url: url))
        try Self.validate(response)
        let decoded = try Self.decoder.decode(T.self, from: data)
        let next = (response as? HTTPURLResponse)
            .flatMap { $0.value(forHTTPHeaderField: "Link") }
            .flatMap(Self.nextPageURL(fromLinkHeader:))
        return (decoded, next)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw GitHubError.http(-1) }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw GitHubError.unauthorized
        case 403:
            // GitHub uses 403 both for missing scope and for rate limiting; the header disambiguates.
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubError.rateLimited
            }
            throw GitHubError.unauthorized
        case 429:
            throw GitHubError.rateLimited
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.http(http.statusCode)
        }
    }

    /// Parses `<https://…?page=2>; rel="next", …` and returns the `next` URL if present.
    static func nextPageURL(fromLinkHeader header: String) -> URL? {
        for part in header.split(separator: ",") {
            let segments = part.split(separator: ";")
            guard segments.count >= 2,
                  segments.contains(where: { $0.contains("rel=\"next\"") }) else { continue }
            let raw = segments[0].trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
            return URL(string: raw)
        }
        return nil
    }

    private static let decoder = JSONDecoder()
}

// MARK: - Wire types

nonisolated struct GitHubUser: Decodable, Sendable {
    let login: String
}

nonisolated struct GitHubIssue: Decodable, Sendable {
    let number: Int
    let title: String
    let body: String?
    let htmlURL: String
    let state: String            // "open" | "closed"
    let stateReason: String?     // "completed" | "not_planned" | "reopened" | nil
    let labels: [GitHubLabel]
    /// Present only when this "issue" is actually a pull request (used to filter PRs out).
    let pullRequest: PullRequestMarker?

    enum CodingKeys: String, CodingKey {
        case number, title, body, state, labels
        case htmlURL = "html_url"
        case stateReason = "state_reason"
        case pullRequest = "pull_request"
    }

    struct PullRequestMarker: Decodable, Sendable {}
}

nonisolated struct GitHubLabel: Decodable, Sendable {
    let name: String
}

// MARK: - Errors

nonisolated enum GitHubError: LocalizedError, Sendable {
    case missingToken
    case badRepositoryURL
    case unauthorized
    case notFound
    case rateLimited
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No GitHub token is set. Add a Personal Access Token in Settings ▸ GitHub."
        case .badRepositoryURL:
            "That doesn't look like a GitHub repository URL (expected https://github.com/owner/repo)."
        case .unauthorized:
            "GitHub rejected the token. Check that it's valid and has read access to Issues."
        case .notFound:
            "Repository not found, or the token can't see it."
        case .rateLimited:
            "GitHub rate limit reached. Wait a bit and try again."
        case .http(let code):
            "GitHub request failed (HTTP \(code))."
        }
    }
}
