import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
import SpaceAPI
@testable import SpacePushClient

/// Hands out one scripted connection per open call and records the requests.
private final class ScriptedStreams: Sendable {
    enum Step: Sendable {
        case respond(Int)
        case send(String)
        case fail(any Error)
    }

    private let scripts: Mutex<[[Step]]>
    private let requests = Mutex<[URLRequest]>([])

    init(_ scripts: [[Step]]) {
        self.scripts = Mutex(scripts)
    }

    var all: [URLRequest] { requests.withLock { $0 } }

    var opener: EventStreamOpener {
        { request in
            self.requests.withLock { $0.append(request) }
            let steps = self.scripts.withLock { $0.isEmpty ? [] : $0.removeFirst() }
            return AsyncThrowingStream { continuation in
                for step in steps {
                    switch step {
                    case .respond(let status):
                        guard (200..<300).contains(status) else {
                            continuation.finish(throwing: SpacePushError.httpStatus(status, reason: "x"))
                            return
                        }
                        let url = request.url!
                        continuation.yield(.response(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!))
                    case .send(let text):
                        continuation.yield(.data(Data(text.utf8)))
                    case .fail(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
        }
    }
}

private let change = """
    event: change
    data: {"endpoint":"https://status.mainframe.io/api/spaceInfo","room":"space","name":"Mainframe","from":"closed","to":"open","at":1}


    """

struct ChangeStreamTests {
    static let base = URL(string: "https://push.example")!
    static let mainframe = URL(string: "https://status.mainframe.io/api/spaceInfo")!

    @Test func buildsStreamRequest() throws {
        let client = SpacePushClient(baseURL: Self.base, headers: ["User-Agent": "spacestate/1"])
        let request = try client.streamRequest(for: [PushSubscription(endpoint: Self.mainframe),
                                                     PushSubscription(endpoint: Self.mainframe, room: "radstelle")])
        #expect(request.url?.absoluteString == "https://push.example/v1/stream"
            + "?sub=https%3A%2F%2Fstatus.mainframe.io%2Fapi%2FspaceInfo"
            + "&sub=https%3A%2F%2Fstatus.mainframe.io%2Fapi%2FspaceInfo%7Cradstelle")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "spacestate/1")
        #expect(request.timeoutInterval == SpacePushClient.streamIdleTimeout)
        let local = try client.streamRequest(for: [PushSubscription(endpoint: Self.mainframe)],
                                             streamBaseURL: URL(string: "http://127.0.0.1:8081")!)
        #expect(local.url?.host == "127.0.0.1" && local.url?.port == 8081)
    }

    @Test func rejectsEmptyOrInvalidSubscriptions() throws {
        let client = SpacePushClient(baseURL: Self.base)
        #expect(throws: EndpointValidationError.invalidEndpoint) { try client.streamRequest(for: []) }
        let invalid = try #require(URL(string: "https://user:secret@space.example/api"))
        #expect(throws: EndpointValidationError.invalidEndpoint) {
            try client.streamRequest(for: [PushSubscription(endpoint: invalid)])
        }
    }

    @Test func deliversConnectedChangesAndRetryHint() async throws {
        let streams = ScriptedStreams([[.respond(200), .send("retry: 10000\n\n: ping\n\n"), .send(change)]])
        let client = SpacePushClient(baseURL: Self.base)
        var events: [ChangeStreamEvent] = []
        for try await event in client.changes(for: [PushSubscription(endpoint: Self.mainframe)], open: streams.opener) {
            events.append(event)
        }
        #expect(events.count == 3)
        #expect(events[0] == .connected)
        #expect(events[1] == .retry(.milliseconds(10000)))
        guard case .change(let received) = events[2] else { Issue.record("Expected a change"); return }
        #expect(received.to == "open")
    }

    @Test func errorAnswersAreThrown() async {
        let streams = ScriptedStreams([[.respond(404)]])
        let client = SpacePushClient(baseURL: Self.base)
        await #expect(throws: SpacePushError.httpStatus(404, reason: "x")) {
            for try await _ in client.changes(for: [PushSubscription(endpoint: Self.mainframe)], open: streams.opener) {}
        }
    }
}
