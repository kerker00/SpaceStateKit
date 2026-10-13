import Foundation
import MainframeStatus
import SpaceAPI

public enum StatusObservationError: Error, Equatable {
    case unprovenProxyObservation
}

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
        try SpaceEndpoint.validate(endpoint)
        return try await read(spacePush.map { client in { try await client.space(at: endpoint) } }) {
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

    /// A stale, future or unproven proxy observation takes the same direct path
    /// as an HTTP failure. A failed fallback is thrown, never stamped as success.
    public func spaceObservation(at endpoint: URL) async throws -> StatusObservation<SpaceInfo> {
        try SpaceEndpoint.validate(endpoint)
        let primary: (@Sendable () async throws -> StatusObservation<SpaceInfo>)?
        if let client = spacePush {
            primary = {
                let observation = try await client.spaceObservation(at: endpoint)
                return try Self.requireCurrent(observation)
            }
        } else {
            primary = nil
        }
        return try await read(primary) {
            try await direct.spaceObservation(at: Self.secure(endpoint))
        }
    }

    public func mainframeRoomsObservation() async throws -> StatusObservation<[MainframeRoom]> {
        let primary: (@Sendable () async throws -> StatusObservation<[MainframeRoom]>)?
        if let client = spacePush {
            primary = {
                let observation = try await client.mainframeRoomsObservation()
                return try Self.requireCurrent(observation)
            }
        } else {
            primary = nil
        }
        return try await read(primary, fallback: direct.mainframeRoomsObservation)
    }

    /// Individual unknown directory entries remain listed and do not force a
    /// fallback or discard current entries. Their effective status stays unknown.
    public func directoryObservations() async throws -> [StatusObservation<DirectoryEntry>] {
        try await read(spacePush?.directoryObservations, fallback: direct.directoryObservations)
    }

    private static func requireCurrent<Value>(_ observation: StatusObservation<Value>) throws -> StatusObservation<Value> {
        guard observation.timing.freshness(at: observation.timing.receivedAt) == .current
        else { throw StatusObservationError.unprovenProxyObservation }
        return observation
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
