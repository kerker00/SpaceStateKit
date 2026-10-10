import Foundation
import MainframeStatus
import SpaceAPI

/// Where the apps get the spaces' state: from SpacePush, which fetches each space
/// once for everyone, and directly from the spaces when SpacePush is unreachable.
/// The apps only connect over HTTPS; SpacePush also reaches spaces that serve plain HTTP.
public struct StatusService: Sendable {
    /// Nil when no SpacePush is configured; then every read goes directly to the spaces.
    public let spacePush: SpacePushClient?
    public let direct: StatusClient

    public init(spacePush: SpacePushClient?, direct: StatusClient = StatusClient()) {
        self.spacePush = spacePush
        self.direct = direct
    }

    public func directory() async throws -> [DirectoryEntry] {
        try await read(spacePush?.directory, fallback: direct.directory)
    }

    public func space(at endpoint: URL) async throws -> SpaceInfo {
        try await read(spacePush.map { client in { try await client.space(at: endpoint) } }) {
            try await direct.space(at: Self.secure(endpoint))
        }
    }

    /// An `http` endpoint as `https`: most of the few spaces listed with `http` also
    /// serve HTTPS, and the apps make no unencrypted requests. SpacePush keeps the
    /// endpoint as listed, since that is how the directory identifies the space.
    static func secure(_ endpoint: URL) -> URL {
        guard endpoint.scheme?.lowercased() == "http",
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else { return endpoint }
        components.scheme = "https"
        if components.port == 80 {
            components.port = nil
        }
        return components.url ?? endpoint
    }

    public func mainframeRooms() async throws -> [MainframeRoom] {
        try await read(spacePush?.mainframeRooms, fallback: direct.mainframeRooms)
    }

    /// Any failure of SpacePush – unreachable, an error status, an unreadable answer –
    /// falls back to the direct read. Cancellation does not.
    private func read<Value>(
        _ primary: (@Sendable () async throws -> Value)?,
        fallback: @Sendable () async throws -> Value
    ) async throws -> Value {
        if let primary {
            do {
                return try await primary()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
            }
        }
        return try await fallback()
    }
}
