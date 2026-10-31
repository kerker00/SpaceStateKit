import Foundation

/// One dispatched server-sent event. `event` is `"message"` when the server names none.
public struct ServerSentEvent: Sendable, Equatable {
    public var event: String
    public var data: String

    public init(event: String = "message", data: String) {
        self.event = event
        self.data = data
    }
}

public enum ServerSentEventError: Error, Equatable {
    /// A line exceeded `ServerSentEventParser.maximumLineBytes` without a line break.
    case lineTooLong
}

/// Incremental parser for `text/event-stream`: feed bytes as they arrive, in chunks of any size.
/// Follows the WHATWG event-stream rules for line endings, comments, `event`, `data` and `retry`;
/// `id` is ignored, because SpacePush replays nothing.
public struct ServerSentEventParser: Sendable {
    public static let maximumLineBytes = 64 * 1024

    /// The last valid `retry:` hint, if any.
    public private(set) var retry: Duration?
    private var line: [UInt8] = []
    private var event = ""
    private var data: [String] = []
    private var skipLineFeed = false

    public init() {}

    public mutating func feed(_ bytes: some Sequence<UInt8>) throws -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if skipLineFeed {
                skipLineFeed = false
                if byte == 0x0A { continue }
            }
            switch byte {
            case 0x0D:
                skipLineFeed = true
                if let event = endLine() { events.append(event) }
            case 0x0A:
                if let event = endLine() { events.append(event) }
            default:
                guard line.count < Self.maximumLineBytes else { throw ServerSentEventError.lineTooLong }
                line.append(byte)
            }
        }
        return events
    }

    private mutating func endLine() -> ServerSentEvent? {
        defer { line.removeAll(keepingCapacity: true) }
        guard !line.isEmpty else { return dispatch() }
        guard line.first != UInt8(ascii: ":") else { return nil }
        let text = String(decoding: line, as: UTF8.self)
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data.append(String(value))
        case "retry":
            if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let ms = Int64(value) {
                retry = .milliseconds(ms)
            }
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer { event = ""; data = [] }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event.isEmpty ? "message" : event, data: data.joined(separator: "\n"))
    }
}
