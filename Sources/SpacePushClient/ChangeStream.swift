import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SpaceAPI

/// What one connection to SpacePush's change stream delivers.
public enum ChangeStreamEvent: Sendable, Equatable {
    /// The stream is open. Read the current state now: events are not replayed.
    case connected
    case change(StateChange)
    /// The server's reconnect hint.
    case retry(Duration)
}

extension SpacePushClient {
    /// Twice SpacePush's 25-second heartbeat: a quiet connection is considered dead after this.
    public static let streamIdleTimeout: TimeInterval = 60

    /// `GET /v1/stream?sub=<endpoint>[|<room>]…` for the subscriptions.
    /// - Parameter streamBaseURL: Where the stream is served, if not at `baseURL`.
    public func streamRequest(for subscriptions: [PushSubscription], streamBaseURL: URL? = nil) throws -> URLRequest {
        let base = streamBaseURL ?? baseURL
        try SpaceEndpoint.validate(base)
        guard !subscriptions.isEmpty else { throw EndpointValidationError.invalidEndpoint }
        for subscription in subscriptions { try SpaceEndpoint.validate(subscription.endpoint) }
        // Strict encoding: the value is a URL itself, and "|" separates the room.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        var components = URLComponents(url: base.appending(components: "v1", "stream"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = subscriptions.map { subscription in
            let value = subscription.room.map { "\(subscription.endpoint.absoluteString)|\($0)" }
                ?? subscription.endpoint.absoluteString
            return "sub=\(value.addingPercentEncoding(withAllowedCharacters: unreserved)!)"
        }.joined(separator: "&")
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: Self.streamIdleTimeout)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// One connection to the change stream. It ends when the server closes the
    /// stream and throws on transport errors, idle timeouts and error answers
    /// (`SpacePushError.httpStatus`). Use `ChangeFeed` to reconnect automatically.
    public func changes(for subscriptions: [PushSubscription], streamBaseURL: URL? = nil,
                        open: EventStreamOpener = EventStreamTransfer.open) -> AsyncThrowingStream<ChangeStreamEvent, any Error> {
        let request: URLRequest
        do {
            request = try streamRequest(for: subscriptions, streamBaseURL: streamBaseURL)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let chunks = open(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = ServerSentEventParser()
                var retry: Duration?
                do {
                    for try await chunk in chunks {
                        switch chunk {
                        case .response:
                            continuation.yield(.connected)
                        case .data(let data):
                            for event in try parser.feed(data) {
                                if let change = try StateChange(event) { continuation.yield(.change(change)) }
                            }
                            if let hint = parser.retry, hint != retry {
                                retry = hint
                                continuation.yield(.retry(hint))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
