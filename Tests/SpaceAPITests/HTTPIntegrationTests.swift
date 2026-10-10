import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SpaceAPI

@Test(.enabled(if: ProcessInfo.processInfo.environment["SPACESTATE_HTTP_TEST_URL"] != nil))
func realHTTPTransport() async throws {
    let base = URL(string: ProcessInfo.processInfo.environment["SPACESTATE_HTTP_TEST_URL"]!)!
    let client = StatusClient()
    #expect(try await client.space(at: base.appendingPathComponent("ok")).status == .open)
    #expect(try await client.space(at: base.appendingPathComponent("redirect")).name == "Test Space")
    await #expect(throws: StatusClientError.httpStatus(503)) {
        try await client.data(from: base.appendingPathComponent("error"))
    }
    for route in ["oversize", "chunked"] {
        await #expect(throws: StatusClientError.responseTooLarge) {
            try await client.data(from: base.appendingPathComponent(route), maximumBytes: 1024)
        }
    }
    // A body above the space-document limit is legal for a directory-sized request.
    #expect(try await client.data(from: base.appendingPathComponent("large"),
                                 maximumBytes: StatusClient.maxDirectoryResponseBytes).count == 300_000)
    await #expect(throws: StatusClientError.responseTooLarge) {
        try await client.data(from: base.appendingPathComponent("large"))
    }
    let slow = base.appendingPathComponent("slow")
    let pending = Task { try await client.data(from: slow) }
    try await Task.sleep(for: .milliseconds(100))
    pending.cancel()
    await #expect(throws: CancellationError.self) { try await pending.value }
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await client.data(from: slow)
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    let request = URLRequest(url: slow, timeoutInterval: 0.2)
    do {
        _ = try await StatusClient.limitedLoad(request)
        Issue.record("Expected a timeout")
    } catch let error as URLError {
        #expect(error.code == .timedOut)
    }
}
