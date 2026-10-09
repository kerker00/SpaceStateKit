import Foundation
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
    /// Sent with every request, e.g. `User-Agent` and `X-SpaceState-Install` for SpacePush's statistics.
    public let headers: [String: String]
    private let load: Loader

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses the shared URL session.
    public init(
        baseURL: URL,
        headers: [String: String] = [:],
        load: @escaping Loader = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.headers = headers
        self.load = load
    }

    /// Registers the device, replacing any earlier registration of the same token.
    /// - Parameter platform: `"ios"` or `"macos"`, for SpacePush's statistics; nil leaves it out.
    public func register(
        deviceToken: Data, environment: PushEnvironment, subscriptions: [PushSubscription], platform: String? = nil
    ) async throws {
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
        try await send(request(for: deviceToken, method: "DELETE"))
    }

    /// The list of spaces, in the aggregator's format.
    public func directory() async throws -> [DirectoryEntry] {
        try SpaceDirectory.decode(await get(path: ["v1", "directory"]))
    }

    /// A space's SpaceAPI document as SpacePush last fetched it, at most a minute old.
    public func space(at endpoint: URL) async throws -> SpaceInfo {
        let data = try await get(path: ["v1", "spaces"], query: ["endpoint": endpoint.absoluteString])
        return try JSONDecoder().decode(SpaceInfo.self, from: data)
    }

    public func mainframeRooms() async throws -> [MainframeRoom] {
        try Mainframe.decodeRooms(await get(path: ["v1", "mainframe", "rooms"]))
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

    private func get(path: [String], query: [String: String] = [:]) async throws -> Data {
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
        return try await send(request)
    }

    private func request(for deviceToken: Data, method: String) -> URLRequest {
        let url = baseURL.appending(components: "v1", "devices", Self.hex(deviceToken))
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await load(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = try? JSONDecoder().decode(ErrorBody.self, from: data).error
            throw SpacePushError.httpStatus(http.statusCode, reason: reason)
        }
        return data
    }
}
