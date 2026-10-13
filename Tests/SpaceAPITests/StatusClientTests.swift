import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import SpaceAPI

private final class RequestLog: Sendable {
    private let requests = Mutex<[URLRequest]>([])

    var all: [URLRequest] { requests.withLock { $0 } }

    func append(_ request: URLRequest) {
        requests.withLock { $0.append(request) }
    }
}

struct StatusClientTests {
    @Test func rejectsInvalidEndpointsBeforeCallingInjectedLoader() async throws {
        let log = RequestLog()
        let client = StatusClient(load: Self.stub(body: Data(), log: log))
        for string in ["file:///tmp/status", "https://user:secret@space.example/api", "https://space.example/%0a"] {
            let url = try #require(URL(string: string))
            await #expect(throws: EndpointValidationError.invalidEndpoint) { try await client.space(at: url) }
            await #expect(throws: EndpointValidationError.invalidEndpoint) { try await client.data(from: url) }
        }
        #expect(log.all.isEmpty)
    }

    @Test func limitedTransportRejectsInvalidAndMissingURLs() async throws {
        let invalid = URLRequest(url: try #require(URL(string: "file:///tmp/status")))
        await #expect(throws: EndpointValidationError.invalidEndpoint) { try await StatusClient.limitedLoad(invalid) }
        var missing = URLRequest(url: Self.endpoint)
        missing.url = nil
        await #expect(throws: EndpointValidationError.invalidEndpoint) { try await StatusClient.limitedLoad(missing) }
    }

    private static let endpoint = URL(string: "https://status.mainframe.io/api/spaceInfo")!

    private static func stub(status: Int = 200, body: Data, log: RequestLog = RequestLog()) -> StatusClient.Loader {
        { request in
            log.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    @Test func fetchesSpaceFromItsEndpoint() async throws {
        let log = RequestLog()
        let client = StatusClient(load: Self.stub(body: try Fixture.data("mainframe-spaceinfo"), log: log))

        let info = try await client.space(at: Self.endpoint)

        #expect(info.name == "Mainframe")
        let request = try #require(log.all.first)
        #expect(request.url == Self.endpoint)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func fetchesDirectoryFromAggregator() async throws {
        let log = RequestLog()
        let client = StatusClient(load: Self.stub(body: try Fixture.data("aggregator"), log: log))

        let entries = try await client.directory()

        #expect(entries.count == 7)
        #expect(log.all.map(\.url) == [SpaceDirectory.aggregatorURL])
    }

    @Test func throwsOnHTTPError() async {
        let client = StatusClient(load: Self.stub(status: 503, body: Data()))

        await #expect(throws: StatusClientError.httpStatus(503)) {
            try await client.space(at: Self.endpoint)
        }
    }
}
