import Foundation

public enum StatusClientError: Error, Equatable {
    case httpStatus(Int)
}

/// Fetches space data over HTTP.
public struct StatusClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let load: Loader

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses the shared URL session.
    public init(load: @escaping Loader = { try await URLSession.shared.data(for: $0) }) {
        self.load = load
    }

    /// Fetches a space directly from its own endpoint.
    public func space(at endpoint: URL) async throws -> SpaceInfo {
        try JSONDecoder().decode(SpaceInfo.self, from: await data(from: endpoint))
    }

    /// Fetches every listed space from the aggregator.
    public func directory() async throws -> [DirectoryEntry] {
        try SpaceDirectory.decode(await data(from: SpaceDirectory.aggregatorURL))
    }

    /// Fetches raw data, for endpoints beyond SpaceAPI. Throws on non-2xx responses.
    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await load(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StatusClientError.httpStatus(http.statusCode)
        }
        return data
    }
}
