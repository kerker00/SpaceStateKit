import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum StatusClientError: Error, Equatable {
    case httpStatus(Int)
    /// The response exceeded `StatusClient.maxResponseBytes`.
    case responseTooLarge
}

/// Fetches space data over HTTP.
public struct StatusClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let load: Loader?

    /// Larger responses are aborted: endpoints are run by third parties, and a
    /// hostile one must not be able to exhaust the app's memory.
    public static let maxResponseBytes = 256 * 1024

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses a bounded URL session
    ///   with separate limits for space documents and the directory.
    public init(load: Loader? = nil) {
        self.load = load
    }

    @Sendable
    public static func limitedLoad(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await limitedLoad(request, maximumBytes: maxResponseBytes)
    }

    public static let maxDirectoryResponseBytes = 16 * 1024 * 1024

    /// Reads incrementally and cancels the HTTP task before accumulating an oversized body.
    public static func limitedLoad(_ request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw EndpointValidationError.invalidEndpoint }
        try SpaceEndpoint.validate(url)
        return try await BoundedHTTPTransfer(maximumBytes: maximumBytes).load(request)
    }

    /// Fetches a space directly from its own endpoint.
    public func space(at endpoint: URL) async throws -> SpaceInfo {
        try JSONDecoder().decode(SpaceInfo.self, from: await data(from: endpoint))
    }

    /// Fetches every listed space from the aggregator.
    public func directory() async throws -> [DirectoryEntry] {
        try SpaceDirectory.decode(await data(from: SpaceDirectory.aggregatorURL, maximumBytes: Self.maxDirectoryResponseBytes))
    }

    /// Fetches raw data, for endpoints beyond SpaceAPI. Throws on non-2xx responses.
    public func data(from url: URL, maximumBytes: Int = Self.maxResponseBytes) async throws -> Data {
        try SpaceEndpoint.validate(url)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        if let load {
            (data, response) = try await load(request)
        } else {
            (data, response) = try await Self.limitedLoad(request, maximumBytes: maximumBytes)
        }
        guard data.count <= maximumBytes else { throw StatusClientError.responseTooLarge }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StatusClientError.httpStatus(http.statusCode)
        }
        return data
    }
}
