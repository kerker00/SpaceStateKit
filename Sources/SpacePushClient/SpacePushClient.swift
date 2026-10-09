import Foundation

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

/// Registers devices with SpacePush (`PUT` / `DELETE /v1/devices/<token>`).
public struct SpacePushClient: Sendable {
    public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let baseURL: URL
    private let load: Loader

    /// - Parameter load: Performs the request. Tests pass a stub; the default uses the shared URL session.
    public init(baseURL: URL, load: @escaping Loader = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL
        self.load = load
    }

    /// Registers the device, replacing any earlier registration of the same token.
    public func register(
        deviceToken: Data, environment: PushEnvironment, subscriptions: [PushSubscription]
    ) async throws {
        var request = request(for: deviceToken, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(Registration(environment: environment, subscriptions: subscriptions))
        try await send(request)
    }

    /// Removes the device, so it gets no more notifications.
    public func unregister(deviceToken: Data) async throws {
        try await send(request(for: deviceToken, method: "DELETE"))
    }

    /// APNs device tokens travel as lowercase hex.
    public static func hex(_ deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    private struct Registration: Encodable {
        var environment: PushEnvironment
        var subscriptions: [PushSubscription]
    }

    private struct ErrorBody: Decodable {
        var error: String
    }

    private func request(for deviceToken: Data, method: String) -> URLRequest {
        let url = baseURL.appending(components: "v1", "devices", Self.hex(deviceToken))
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        return request
    }

    private func send(_ request: URLRequest) async throws {
        let (data, response) = try await load(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = try? JSONDecoder().decode(ErrorBody.self, from: data).error
            throw SpacePushError.httpStatus(http.statusCode, reason: reason)
        }
    }
}
