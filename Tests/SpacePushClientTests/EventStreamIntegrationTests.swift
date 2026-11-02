import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import SpaceAPI
@testable import SpacePushClient

/// Run by IntegrationTests/run.py against a local server that sends two events a second apart.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SPACESTATE_HTTP_TEST_URL"] != nil))
func realEventStream() async throws {
    let base = URL(string: ProcessInfo.processInfo.environment["SPACESTATE_HTTP_TEST_URL"]!)!
    let client = SpacePushClient(baseURL: base)
    let subscription = [PushSubscription(endpoint: URL(string: "https://a.example/")!)]

    // Each event must arrive when it is sent, not when the response ends.
    let clock = ContinuousClock()
    let start = clock.now
    var arrivals: [(String?, Duration)] = []
    var connected = false
    for try await event in client.changes(for: subscription) {
        switch event {
        case .connected: connected = true
        case .change(let change): arrivals.append((change.to, clock.now - start))
        case .retry(let hint): #expect(hint == .milliseconds(1000))
        }
    }
    #expect(connected)
    #expect(arrivals.map(\.0) == ["open", "closed"])
    #expect(arrivals[0].1 < .milliseconds(700))
    #expect(arrivals[1].1 - arrivals[0].1 > .milliseconds(700))

    await #expect(throws: SpacePushError.httpStatus(404, reason: "unknown_space")) {
        for try await _ in client.changes(for: subscription, streamBaseURL: base.appending(component: "missing")) {}
    }

    // Cancelling an open stream must release the session cleanly (no crash at teardown).
    for _ in 0..<5 {
        let open = Task {
            for try await _ in client.changes(for: subscription, streamBaseURL: base.appending(component: "quiet")) {}
        }
        try await Task.sleep(for: .milliseconds(200))
        open.cancel()
        _ = await open.result
    }
    try await Task.sleep(for: .milliseconds(500))

    // A silent connection ends at the request's idle limit.
    var request = try client.streamRequest(for: subscription, streamBaseURL: base.appending(component: "quiet"))
    request.timeoutInterval = 0.5
    do {
        for try await _ in EventStreamTransfer.open(request) {}
        Issue.record("Expected an idle timeout")
    } catch let error as URLError {
        #expect(error.code == .timedOut)
    }
}
