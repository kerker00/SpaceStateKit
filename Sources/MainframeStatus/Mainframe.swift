import Foundation
import SpaceAPI

/// Mainframe Oldenburg is the one space with extra support: its status server reports
/// several rooms and finer states than SpaceAPI can express.
public enum Mainframe {
    public static let spaceAPIEndpoint = URL(string: "https://status.mainframe.io/api/spaceInfo")!
    public static let openStateURL = URL(string: "https://status.kreativitaet-trifft-technik.de/api/openState")!

    public static func isMainframe(_ endpoint: URL) -> Bool {
        endpoint.host()?.lowercased() == spaceAPIEndpoint.host()
    }

    /// Decodes an openState response into rooms, in a stable display order.
    public static func decodeRooms(_ data: Data) throws -> [MainframeRoom] {
        try JSONDecoder().decode([String: RawRoom].self, from: data)
            .compactMap { id, raw in
                guard let state = raw.state else { return nil }
                return MainframeRoom(id: id, state: MainframeRoomState(rawValue: state), since: raw.timestamp)
            }
            .sorted { lhs, rhs in
                let lhsOrder = MainframeRoom.displayOrder.firstIndex(of: lhs.id) ?? .max
                let rhsOrder = MainframeRoom.displayOrder.firstIndex(of: rhs.id) ?? .max
                return lhsOrder == rhsOrder ? lhs.id < rhs.id : lhsOrder < rhsOrder
            }
    }

    private struct RawRoom: Decodable {
        var state: String?
        var timestamp: Date?

        private enum CodingKeys: String, CodingKey {
            case state, timestamp
        }

        // Never throws, so one broken room cannot hide the others.
        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            state = (try? container?.decodeIfPresent(String.self, forKey: .state)) ?? nil
            timestamp = ((try? container?.decodeIfPresent(Double.self, forKey: .timestamp)) ?? nil)
                .map(Date.init(timeIntervalSince1970:))
        }
    }
}

public struct MainframeRoom: Sendable, Hashable, Identifiable {
    /// The key used by the status server, e.g. "space" or "radstelle".
    public var id: String
    public var state: MainframeRoomState
    public var since: Date?

    static let displayOrder = ["space", "radstelle", "lab3d", "machining", "woodworking"]

    public init(id: String, state: MainframeRoomState, since: Date?) {
        self.id = id
        self.state = state
        self.since = since
    }

    public var name: String {
        switch id {
        case "space": "Space"
        case "radstelle": "Radstelle"
        case "lab3d": "3D Lab"
        case "machining": "Machining"
        case "woodworking": "Woodworking"
        default: id
        }
    }
}

/// The states the Mainframe status server reports (see ktt-ol/spacestatus2, openValues.go).
public enum MainframeRoomState: Sendable, Hashable {
    case closed
    case keyholder
    case member
    case open
    case openPlus
    case closing
    case unknown(String)

    public init(rawValue: String) {
        self = switch rawValue {
        case "none", "off", "closed": .closed
        case "keyholder": .keyholder
        case "member": .member
        case "open", "on", "opened": .open
        case "open+": .openPlus
        case "closing": .closing
        default: .unknown(rawValue)
        }
    }

    /// Only "open" and "open+" mean guests are welcome; everything else counts as closed.
    public var status: SpaceStatus {
        switch self {
        case .open, .openPlus: .open
        case .closed, .keyholder, .member, .closing: .closed
        case .unknown: .unknown
        }
    }
}

extension StatusClient {
    public func mainframeRooms() async throws -> [MainframeRoom] {
        try Mainframe.decodeRooms(await data(from: Mainframe.openStateURL))
    }
}
