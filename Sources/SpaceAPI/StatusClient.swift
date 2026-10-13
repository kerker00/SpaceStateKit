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
    private let now: @Sendable () -> Date
    private let maximumObservationAge: TimeInterval

    /// Larger responses are aborted: endpoints are run by third parties, and a
    /// hostile one must not be able to exhaust the app's memory.
    public static let maxResponseBytes = 256 * 1024

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses a bounded URL session
    ///   with separate limits for space documents and the directory.
    public init(load: Loader? = nil) {
        self.init(now: { Date() }, load: load)
    }

    /// Injectable clock and direct-read policy, without changing the legacy
    /// loader initializer or its trailing-closure syntax.
    public init(maximumObservationAge: TimeInterval = ObservationTiming.defaultMaximumAge,
                now: @escaping @Sendable () -> Date, load: Loader? = nil) {
        self.load = load
        self.now = now
        self.maximumObservationAge = maximumObservationAge
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

    /// A direct successful fetch provides a receipt observation, not a physical
    /// measurement timestamp. `state.lastchange` does not determine its age.
    public func spaceObservation(at endpoint: URL) async throws -> StatusObservation<SpaceInfo> {
        let observation = try await dataObservation(from: endpoint)
        return StatusObservation(value: try JSONDecoder().decode(SpaceInfo.self, from: observation.value),
                                 timing: observation.timing)
    }

    /// Each entry retains its own original lastSeen. Missing observations are
    /// unknown, even though the directory document was just received successfully.
    public func directoryObservations() async throws -> [StatusObservation<DirectoryEntry>] {
        let document = try await dataObservation(from: SpaceDirectory.aggregatorURL,
                                                 maximumBytes: Self.maxDirectoryResponseBytes)
        return try SpaceDirectory.decode(document.value).map { entry in
            StatusObservation(value: entry, timing: ObservationTiming(source: .aggregator,
                observedAt: entry.lastSeen, receivedAt: document.timing.receivedAt,
                maximumAge: maximumObservationAge, sourceReachable: entry.reachable))
        }
    }

    public func dataObservation(from url: URL, maximumBytes: Int = Self.maxResponseBytes) async throws -> StatusObservation<Data> {
        let data = try await data(from: url, maximumBytes: maximumBytes)
        let receivedAt = now()
        return StatusObservation(value: data, timing: ObservationTiming(source: .direct,
            observedAt: receivedAt, receivedAt: receivedAt, maximumAge: maximumObservationAge))
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
