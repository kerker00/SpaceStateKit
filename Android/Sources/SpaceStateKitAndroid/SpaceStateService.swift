import Foundation
import MainframeStatus
import SpaceAPI
import SpacePushClient

/// The Android app's entry point into SpaceStateKit. Uses only types swift-java bridges
/// cleanly: strings for URLs, seconds since 1970 for dates, plain enums and final classes.
public final class SpaceStateService: Sendable {
    private let service: StatusService
    private let invalidConfiguration: Bool

    /// - Parameters:
    ///   - spacePushURL: SpacePush's base URL; nil reads every space directly.
    ///   - userAgent: Sent to SpacePush, e.g. `SpaceState/1.0 (Android 16)`.
    ///   - activePeriodsFile: Where the reported day, week and month labels are kept;
    ///     nil reports none (widgets).
    public init(spacePushURL: String?, userAgent: String, activePeriodsFile: String?) {
        let baseURL = spacePushURL.flatMap { try? SpaceEndpoint.parse($0) }
        invalidConfiguration = spacePushURL != nil && baseURL == nil
        let periods = activePeriodsFile.map(ActivePeriods.file(path:))
        service = StatusService(spacePush: baseURL.map {
            SpacePushClient(baseURL: $0, headers: ["User-Agent": userAgent], activePeriods: periods)
        })
    }

    // Host-side tests exercise the production facade without generating JNI bindings.
    init(service: StatusService) {
        self.service = service
        invalidConfiguration = false
    }

    public static let mainframeEndpoint: String = Mainframe.spaceAPIEndpoint.absoluteString

    public static func isMainframe(endpoint: String) -> Bool {
        (try? SpaceEndpoint.parse(endpoint)).map(Mainframe.isMainframe) ?? false
    }

    public func space(endpoint: String) async throws -> Space {
        try await classified {
            let url = try SpaceEndpoint.parse(endpoint)
            return Space(endpoint: endpoint, info: try await service.space(at: url))
        }
    }

    public func mainframeRooms() async throws -> [Room] {
        try await classified { try await service.mainframeRooms().map(Room.init) }
    }

    public func directory() async throws -> [DirectoryItem] {
        try await classified { try await service.directory().map(DirectoryItem.init) }
    }

    /// Additive observation reads. Legacy value-only methods retain their signatures.
    public func spaceObservation(endpoint: String) async throws -> ObservedSpace {
        try await classified {
            let url = try SpaceEndpoint.parse(endpoint)
            return ObservedSpace(endpoint: endpoint, observation: try await service.spaceObservation(at: url))
        }
    }

    public func mainframeRoomsObservation() async throws -> ObservedRooms {
        try await classified { ObservedRooms(try await service.mainframeRoomsObservation()) }
    }

    public func directoryObservations() async throws -> [ObservedDirectoryItem] {
        try await classified { try await service.directoryObservations().map(ObservedDirectoryItem.init) }
    }

    private func classified<Value>(_ body: () async throws -> Value) async throws -> Value {
        do {
            guard !invalidConfiguration else { throw ServiceError.invalidEndpoint }
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError(error)
        }
    }
}

/// What went wrong, reduced to cases the app explains in its own language.
///
/// swift-java hands a thrown error to Java as an exception whose message is
/// `String(describing:)`, so the description is a stable code the Kotlin layer parses:
/// `spacestatekit:<kind>[:<detail>]`. Foundation's own descriptions on Android are
/// raw `NSError` dumps without localization.
enum ServiceError: Error, CustomStringConvertible {
    /// No connection, or the host could not be found or reached.
    case unreachable
    case timeout
    case httpStatus(Int)
    case responseTooLarge
    /// The answer was not a readable SpaceAPI document, directory or room list.
    case invalidData
    case invalidEndpoint
    case other(String)

    init(_ error: any Error) {
        switch error {
        case let error as ServiceError:
            self = error
        case is EndpointValidationError:
            self = .invalidEndpoint
        case StatusClientError.httpStatus(let code), SpacePushError.httpStatus(let code, _):
            self = .httpStatus(code)
        case StatusClientError.responseTooLarge:
            self = .responseTooLarge
        case is DecodingError:
            self = .invalidData
        default:
            let error = error as NSError
            guard error.domain == NSURLErrorDomain else {
                self = .other(String(describing: error))
                return
            }
            switch error.code {
            case NSURLErrorTimedOut:
                self = .timeout
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorSecureConnectionFailed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
                self = .unreachable
            default:
                self = .other("\(error.domain) \(error.code)")
            }
        }
    }

    var description: String {
        switch self {
        case .unreachable: "spacestatekit:unreachable"
        case .timeout: "spacestatekit:timeout"
        case .httpStatus(let code): "spacestatekit:http:\(code)"
        case .responseTooLarge: "spacestatekit:tooLarge"
        case .invalidData: "spacestatekit:invalidData"
        case .invalidEndpoint: "spacestatekit:invalidEndpoint"
        case .other(let detail): "spacestatekit:other:\(detail)"
        }
    }
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
    public let details: SpaceDetails

    init(endpoint: String, info: SpaceInfo) {
        self.endpoint = endpoint
        name = info.name
        status = Status(info.status)
        lastChange = ReadTiming.timestamp(info.state?.lastChange)
        message = info.state?.message
        website = info.website?.absoluteString
        logo = info.logo?.absoluteString
        address = info.location?.address
        details = SpaceDetails(info)
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
        since = ReadTiming.timestamp(room.since)
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


/// Observation evidence in JNI-compatible fields. No client-time substitutes for
/// missing lastSeen, and no platform-dependent conversion of nonfinite dates.
public final class ReadTiming: Sendable {
    /// "direct", "aggregator" or "spacePush"; identifies the read path.
    public let source: String
    /// Original successful observation, in seconds since 1970.
    public let observedAt: Double?
    /// Successful client receipt, independent of a later failed attempt.
    public let receivedAt: Double?
    /// Conservative SDK expiry, including an earlier proxy limit or reachability failure.
    public let expiresAt: Double?

    init(_ timing: ObservationTiming) {
        source = timing.source.rawValue
        receivedAt = Self.timestamp(timing.receivedAt)
        if let observed = Self.timestamp(timing.observedAt), let receivedAt, observed <= receivedAt {
            observedAt = observed
        } else {
            observedAt = nil
        }
        expiresAt = observedAt != nil && receivedAt != nil ? Self.timestamp(timing.expiresAt) : nil
    }

    // A shared portable range also keeps Android date/duration UI conversions safe.
    static func timestamp(_ date: Date?) -> Double? {
        guard let seconds = date?.timeIntervalSince1970, seconds.isFinite,
              (0...253_402_300_799).contains(seconds) else { return nil }
        return seconds
    }
}

/// Keep the reported value alongside timing; evaluate timing again when displaying.
public final class ObservedSpace: Sendable {
    public let value: Space
    public let timing: ReadTiming

    init(endpoint: String, observation: StatusObservation<SpaceInfo>) {
        value = Space(endpoint: endpoint, info: observation.value)
        timing = ReadTiming(observation.timing)
    }
}

/// The whole room document has one observation even when its decoded list is empty.
public final class ObservedRooms: Sendable {
    public let values: [Room]
    public let timing: ReadTiming

    init(_ observation: StatusObservation<[MainframeRoom]>) {
        values = observation.value.map(Room.init)
        timing = ReadTiming(observation.timing)
    }
}

/// Each directory entry retains its own original observation and expiry.
public final class ObservedDirectoryItem: Sendable {
    public let value: DirectoryItem
    public let timing: ReadTiming

    init(_ observation: StatusObservation<DirectoryEntry>) {
        value = DirectoryItem(observation.value)
        timing = ReadTiming(observation.timing)
    }
}
