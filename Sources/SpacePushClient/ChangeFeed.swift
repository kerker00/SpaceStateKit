import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What a `ChangeFeed` reports while it keeps a change stream open.
public enum ChangeFeedEvent: Sendable, Equatable {
    /// A connection is open. Read the current state now; events missed while
    /// disconnected are not replayed.
    case connected
    case change(StateChange)
    /// The connection ended; the feed reconnects after `retryIn`.
    case disconnected(reason: String, retryIn: Duration)
}

/// Keeps SpacePush's change stream open: reconnects with jittered exponential
/// backoff after failures, and after the server's `retry` hint when a stream ends normally.
/// Answers 400 and 404 (invalid or unknown subscriptions) end the feed with that error.
public struct ChangeFeed: Sendable {
    public typealias Sleep = @Sendable (Duration) async throws -> Void
    /// Returns the delay to wait for a nominal delay, e.g. a random share of it.
    public typealias Jitter = @Sendable (Duration) -> Duration

    public let client: SpacePushClient
    public let subscriptions: [PushSubscription]
    public let streamBaseURL: URL?
    public let minimumDelay: Duration
    public let maximumDelay: Duration
    private let open: EventStreamOpener
    private let sleep: Sleep
    private let jitter: Jitter

    public init(client: SpacePushClient, subscriptions: [PushSubscription], streamBaseURL: URL? = nil,
                minimumDelay: Duration = .seconds(1), maximumDelay: Duration = .seconds(300),
                open: @escaping EventStreamOpener = EventStreamTransfer.open,
                sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
                jitter: @escaping Jitter = ChangeFeed.halfJitter) {
        self.client = client
        self.subscriptions = subscriptions
        self.streamBaseURL = streamBaseURL
        self.minimumDelay = minimumDelay
        self.maximumDelay = maximumDelay
        self.open = open
        self.sleep = sleep
        self.jitter = jitter
    }

    /// Waits between half and all of the nominal delay, so clients do not reconnect in lockstep.
    public static let halfJitter: Jitter = { delay in
        delay / 2 + delay / 2 * Double.random(in: 0...1)
    }

    /// The nominal delay after `failures` consecutive failed attempts (1, 2, 4 … seconds, capped).
    public func backoff(failures: Int) -> Duration {
        var delay = minimumDelay
        for _ in 1..<max(failures, 1) {
            delay *= 2
            if delay >= maximumDelay { return maximumDelay }
        }
        return min(delay, maximumDelay)
    }

    public func events() -> AsyncThrowingStream<ChangeFeedEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var failures = 0
                var hint = Duration.seconds(10)
                while !Task.isCancelled {
                    var delay: Duration
                    var reason = "stream ended"
                    do {
                        for try await event in client.changes(for: subscriptions, streamBaseURL: streamBaseURL, open: open) {
                            switch event {
                            case .connected:
                                failures = 0
                                continuation.yield(.connected)
                            case .change(let change):
                                continuation.yield(.change(change))
                            case .retry(let duration):
                                hint = duration
                            }
                        }
                        delay = max(hint, minimumDelay)
                    } catch is CancellationError {
                        break
                    } catch SpacePushError.httpStatus(let status, let error) where status == 400 || status == 404 {
                        continuation.finish(throwing: SpacePushError.httpStatus(status, reason: error))
                        return
                    } catch {
                        failures += 1
                        delay = backoff(failures: failures)
                        reason = String(describing: error)
                    }
                    if Task.isCancelled { break }
                    let wait = jitter(delay)
                    continuation.yield(.disconnected(reason: reason, retryIn: wait))
                    do { try await sleep(wait) } catch { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
