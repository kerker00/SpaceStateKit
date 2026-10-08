import Foundation
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
