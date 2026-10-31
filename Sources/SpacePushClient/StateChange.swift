import Foundation

/// A confirmed change from SpacePush's change stream, or a test event.
public struct StateChange: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case change
        case test
    }

    public var kind: Kind
    /// The space's SpaceAPI endpoint.
    public var endpoint: URL
    /// `"space"` for the space itself, or a Mainframe room such as `"radstelle"`.
    public var room: String
    /// The cleaned title SpacePush also uses for APNs alerts, including the room.
    public var name: String
    /// The previous and new state, such as `"closed"` and `"open"`; nil for test events.
    /// States are kept as strings, so a state added later on the server is not a decoding error.
    public var from: String?
    public var to: String?
    /// When SpacePush sent the event.
    public var at: Date

    public init(kind: Kind, endpoint: URL, room: String, name: String, from: String?, to: String?, at: Date) {
        self.kind = kind
        self.endpoint = endpoint
        self.room = room
        self.name = name
        self.from = from
        self.to = to
        self.at = at
    }

    /// The subscription this change belongs to.
    public var subscription: PushSubscription {
        PushSubscription(endpoint: endpoint, room: room == "space" ? nil : room)
    }

    /// Decodes a `change` or `test` event; other events give nil.
    public init?(_ event: ServerSentEvent) throws {
        guard let kind = Kind(rawValue: event.event) else { return nil }
        let body = try JSONDecoder().decode(Body.self, from: Data(event.data.utf8))
        guard let endpoint = URL(string: body.endpoint) else { throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Invalid endpoint")) }
        if kind == .change, body.from == nil || body.to == nil {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Change without states"))
        }
        self.init(kind: kind, endpoint: endpoint, room: body.room, name: body.name,
                  from: body.from, to: body.to, at: Date(timeIntervalSince1970: TimeInterval(body.at)))
    }

    private struct Body: Decodable {
        var endpoint: String
        var room: String
        var name: String
        var from: String?
        var to: String?
        var at: Int64
    }
}
