import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient

/// The Android app's entry point into SpaceStateKit. Uses only types swift-java bridges
/// cleanly: strings for URLs, seconds since 1970 for dates, plain enums and final classes.
public final class SpaceStateService: Sendable {
    private let service: StatusService

    /// - Parameters:
    ///   - spacePushURL: SpacePush's base URL; nil reads every space directly.
    ///   - userAgent: Sent to SpacePush, e.g. `SpaceState/1.0 (Android 16)`.
    ///   - activePeriodsFile: Where the reported day, week and month labels are kept;
    ///     nil reports none (widgets).
    public init(spacePushURL: String?, userAgent: String, activePeriodsFile: String?) {
        let periods = activePeriodsFile.map(ActivePeriods.file(path:))
        service = StatusService(spacePush: spacePushURL.flatMap(URL.init(string:)).map {
            SpacePushClient(baseURL: $0, headers: ["User-Agent": userAgent], activePeriods: periods)
        })
    }

    public static let mainframeEndpoint: String = Mainframe.spaceAPIEndpoint.absoluteString

    public static func isMainframe(endpoint: String) -> Bool {
        URL(string: endpoint).map(Mainframe.isMainframe) ?? false
    }

    public func space(endpoint: String) async throws -> Space {
        guard let url = URL(string: endpoint) else { throw SpaceStateServiceError.invalidEndpoint(endpoint) }
        return Space(endpoint: endpoint, info: try await service.space(at: url))
    }

    public func mainframeRooms() async throws -> [Room] {
        try await service.mainframeRooms().map(Room.init)
    }

    public func directory() async throws -> [DirectoryItem] {
        try await service.directory().map(DirectoryItem.init)
    }
}

public enum SpaceStateServiceError: Error {
    case invalidEndpoint(String)
}

public enum Status: Sendable {
    case open, closed, unknown

    init(_ status: SpaceStatus) {
        self = switch status {
        case .open: .open
        case .closed: .closed
        case .unknown: .unknown
        }
    }
}

public final class Space: Sendable {
    public let endpoint: String
    public let name: String
    public let status: Status
    /// Seconds since 1970.
    public let lastChange: Double?
    public let message: String?
    public let website: String?
    public let logo: String?
    public let address: String?

    init(endpoint: String, info: SpaceInfo) {
        self.endpoint = endpoint
        name = info.name
        status = Status(info.status)
        lastChange = info.state?.lastChange?.timeIntervalSince1970
        message = info.state?.message
        website = info.website?.absoluteString
        logo = info.logo?.absoluteString
        address = info.location?.address
    }
}

public enum RoomState: Sendable {
    case closed, keyholder, member, open, openPlus, closing, unknown
}

public final class Room: Sendable {
    /// The status server's key, e.g. "space" or "radstelle"; also the push subscription's room.
    public let id: String
    public let name: String
    public let state: RoomState
    /// The status server's value, shown for unknown states.
    public let rawState: String
    /// Seconds since 1970.
    public let since: Double?

    init(_ room: MainframeRoom) {
        id = room.id
        name = room.name
        since = room.since?.timeIntervalSince1970
        switch room.state {
        case .closed: (state, rawState) = (.closed, "none")
        case .keyholder: (state, rawState) = (.keyholder, "keyholder")
        case .member: (state, rawState) = (.member, "member")
        case .open: (state, rawState) = (.open, "open")
        case .openPlus: (state, rawState) = (.openPlus, "open+")
        case .closing: (state, rawState) = (.closing, "closing")
        case .unknown(let raw): (state, rawState) = (.unknown, raw)
        }
    }
}

public final class DirectoryItem: Sendable {
    public let endpoint: String
    public let name: String
    public let address: String?
    public let status: Status

    init(_ entry: DirectoryEntry) {
        endpoint = entry.endpoint.absoluteString
        name = entry.info.name
        address = entry.info.location?.address
        status = Status(entry.info.status)
    }
}
