import Foundation

public enum StatusClientError: Error, Equatable {
    case httpStatus(Int)
    /// The response exceeded `StatusClient.maxResponseBytes`.
    case responseTooLarge
}

/// Fetches space data over HTTP.
public struct StatusClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let load: Loader

    /// Larger responses are aborted: endpoints are run by third parties, and a
    /// hostile one must not be able to exhaust the app's memory.
    public static let maxResponseBytes = 256 * 1024

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses the shared URL session
    ///   and stops reading after `maxResponseBytes`.
    public init(load: @escaping Loader = StatusClient.limitedLoad) {
        self.load = load
    }

    @Sendable
    public static func limitedLoad(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if response.expectedContentLength > Int64(maxResponseBytes) {
            throw StatusClientError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxResponseBytes {
                throw StatusClientError.responseTooLarge
            }
        }
        return (data, response)
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
