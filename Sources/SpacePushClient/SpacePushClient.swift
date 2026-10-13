import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MainframeStatus
import SpaceAPI

/// The APNs environment a device token belongs to.
public enum PushEnvironment: String, Sendable, Hashable, Encodable {
    /// Builds signed for development, e.g. run from Xcode.
    case sandbox
    /// TestFlight and App Store builds.
    case production
}

/// A space, or one of Mainframe's rooms, a device wants notifications for.
public struct PushSubscription: Sendable, Hashable, Encodable {
    /// The space's SpaceAPI endpoint.
    public var endpoint: URL
    /// Nil for the space itself; a room name such as "radstelle" for Mainframe.
    public var room: String?

    public init(endpoint: URL, room: String? = nil) {
        self.endpoint = endpoint
        self.room = room
    }
}

public enum SpacePushError: Error, Equatable {
    /// The service rejected the request; `reason` is its error code, e.g. "registry_full".
    case httpStatus(Int, reason: String?)
}

/// Talks to SpacePush: registers devices (`PUT` / `DELETE /v1/devices/<token>`) and reads
/// the spaces' state, which SpacePush fetches once for all users (`GET /v1/…`).
public struct SpacePushClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let baseURL: URL
    /// Sent with every request, e.g. `User-Agent` for SpacePush's statistics.
    public let headers: [String: String]
    /// Reports the first request of each day, week and month in `X-SpaceState-First`; nil sends nothing.
    public let activePeriods: ActivePeriods?
    private let load: Loader?
    private let now: @Sendable () -> Date

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses a bounded URL session.
    public init(
        baseURL: URL,
        headers: [String: String] = [:],
        activePeriods: ActivePeriods? = nil,
        load: Loader? = nil
    ) {
        self.init(baseURL: baseURL, headers: headers, activePeriods: activePeriods, now: { Date() }, load: load)
    }

    /// Injectable receipt clock; the existing loader initializer is preserved.
    public init(
        baseURL: URL,
        headers: [String: String] = [:],
        activePeriods: ActivePeriods? = nil,
        now: @escaping @Sendable () -> Date,
        load: Loader? = nil
    ) {
        self.baseURL = baseURL
        self.headers = headers
        self.activePeriods = activePeriods
        self.load = load
        self.now = now
    }

    /// Registers the device, replacing any earlier registration of the same token.
    /// - Parameter platform: `"ios"` or `"macos"`, for SpacePush's statistics; nil leaves it out.
    public func register(
        deviceToken: Data, environment: PushEnvironment, subscriptions: [PushSubscription], platform: String? = nil
    ) async throws {
        try SpaceEndpoint.validate(baseURL)
        for subscription in subscriptions { try SpaceEndpoint.validate(subscription.endpoint) }
        var request = request(for: deviceToken, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(
            Registration(environment: environment, platform: platform, subscriptions: subscriptions)
        )
        try await send(request)
    }

    /// Removes the device, so it gets no more notifications.
    public func unregister(deviceToken: Data) async throws {
        try SpaceEndpoint.validate(baseURL)
        try await send(request(for: deviceToken, method: "DELETE"))
    }

    /// The list of spaces, in the aggregator's format.
    public func directory() async throws -> [DirectoryEntry] {
        try SpaceDirectory.decode(await get(path: ["v1", "directory"], maximumBytes: StatusClient.maxDirectoryResponseBytes))
    }

    /// A space's SpaceAPI document as SpacePush last fetched it. This legacy API
    /// omits observation evidence; use spaceObservation(at:) for freshness.
    public func space(at endpoint: URL) async throws -> SpaceInfo {
        try SpaceEndpoint.validate(endpoint)
        let data = try await get(path: ["v1", "spaces"], query: ["endpoint": endpoint.absoluteString])
        return try JSONDecoder().decode(SpaceInfo.self, from: data)
    }

    public func mainframeRooms() async throws -> [MainframeRoom] {
        try Mainframe.decodeRooms(await get(path: ["v1", "mainframe", "rooms"]))
    }

    /// Retains proxy fetch time instead of stamping a cached response as new.
    /// Missing or invalid headers provide unknown timing, preserving the value.
    public func spaceObservation(at endpoint: URL) async throws -> StatusObservation<SpaceInfo> {
        try SpaceEndpoint.validate(endpoint)
        let answer = try await getResponse(path: ["v1", "spaces"], query: ["endpoint": endpoint.absoluteString])
        return StatusObservation(value: try JSONDecoder().decode(SpaceInfo.self, from: answer.data),
                                 timing: observationTiming(answer))
    }

    public func mainframeRoomsObservation() async throws -> StatusObservation<[MainframeRoom]> {
        let answer = try await getResponse(path: ["v1", "mainframe", "rooms"])
        return StatusObservation(value: try Mainframe.decodeRooms(answer.data), timing: observationTiming(answer))
    }

    /// Per-entry lastSeen is the evidence, not the time the list was downloaded.
    public func directoryObservations() async throws -> [StatusObservation<DirectoryEntry>] {
        let answer = try await getResponse(path: ["v1", "directory"], maximumBytes: StatusClient.maxDirectoryResponseBytes)
        let maximumAge = observationAge(answer.response)
        return try SpaceDirectory.decode(answer.data).map { entry in
            StatusObservation(value: entry, timing: ObservationTiming(source: .spacePush,
                observedAt: entry.lastSeen, receivedAt: answer.receivedAt, maximumAge: maximumAge,
                sourceReachable: entry.reachable))
        }
    }

    /// APNs device tokens travel as lowercase hex.
    public static func hex(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    private struct Registration: Encodable {
        var environment: PushEnvironment
        var platform: String?
        var subscriptions: [PushSubscription]
    }

    private struct ErrorBody: Decodable {
        var error: String
    }

    private func get(path: [String], query: [String: String] = [:], maximumBytes: Int = StatusClient.maxResponseBytes) async throws -> Data {
        try await getResponse(path: path, query: query, maximumBytes: maximumBytes).data
    }

    private func getResponse(path: [String], query: [String: String] = [:], maximumBytes: Int = StatusClient.maxResponseBytes) async throws -> ReadResponse {
        try SpaceEndpoint.validate(baseURL)
        var url = baseURL
        for component in path {
            url.append(component: component)
        }
        if !query.isEmpty {
            // Strict encoding: the value is a URL itself, and the server reads "+" as a space.
            let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.percentEncodedQuery = query.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved)!)" }
                .joined(separator: "&")
            url = components.url!
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await sendResponse(request, maximumBytes: maximumBytes)
    }

    private func request(for deviceToken: Data, method: String) -> URLRequest {
        let url = baseURL.appending(components: "v1", "devices", Self.hex(deviceToken))
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest, maximumBytes: Int = StatusClient.maxResponseBytes) async throws -> Data {
        try await sendResponse(request, maximumBytes: maximumBytes).data
    }

    private struct ReadResponse {
        let data: Data
        let response: URLResponse
        let receivedAt: Date
    }

    private func sendResponse(_ request: URLRequest, maximumBytes: Int = StatusClient.maxResponseBytes) async throws -> ReadResponse {
        guard let url = request.url else { throw EndpointValidationError.invalidEndpoint }
        try SpaceEndpoint.validate(url)
        var request = request
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let report = activePeriods?.begin()
        if let report {
            request.setValue(report.value, forHTTPHeaderField: "X-SpaceState-First")
        }
        let data: Data
        let response: URLResponse
        do {
            if let load {
                (data, response) = try await load(request)
            } else {
                (data, response) = try await StatusClient.limitedLoad(request, maximumBytes: maximumBytes)
            }
            guard data.count <= maximumBytes else { throw StatusClientError.responseTooLarge }
        } catch {
            activePeriods?.finish(report, delivered: false)
            throw error
        }
        // SpacePush counts every request it answers, errors included.
        activePeriods?.finish(report, delivered: true)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = try? JSONDecoder().decode(ErrorBody.self, from: data).error
            throw SpacePushError.httpStatus(http.statusCode, reason: reason)
        }
        return ReadResponse(data: data, response: response, receivedAt: now())
    }

    private func observationAge(_ response: URLResponse) -> TimeInterval {
        guard let field = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-SpacePush-Max-Data-Age")
        else { return ObservationTiming.defaultMaximumAge }
        // A present malformed policy must not quietly become the default policy.
        return Self.seconds(field).flatMap { $0 > 0 ? $0 : nil } ?? 0
    }

    private func observationTiming(_ answer: ReadResponse) -> ObservationTiming {
        let http = answer.response as? HTTPURLResponse
        let fetched = http?.value(forHTTPHeaderField: "X-SpacePush-Fetched-At").flatMap(Self.seconds)
        let expiryField = http?.value(forHTTPHeaderField: "X-SpacePush-Expires-At")
        let expiry = expiryField.flatMap(Self.seconds)
        let validExpiry = expiryField == nil || expiry != nil
        return ObservationTiming(source: .spacePush,
            observedAt: validExpiry ? fetched.map(Date.init(timeIntervalSince1970:)) : nil,
            receivedAt: answer.receivedAt, maximumAge: observationAge(answer.response),
            advertisedExpiresAt: expiry.map(Date.init(timeIntervalSince1970:)))
    }

    private static func seconds(_ field: String) -> TimeInterval? {
        let text = field.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int64(text) else { return nil }
        return TimeInterval(value)
    }
}
