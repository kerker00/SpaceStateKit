import Foundation
import MainframeStatus
import SpaceAPI
import Synchronization
import Testing
@testable import SpacePushClient

/// Answers requests by URL prefix and records them.
private final class FakeServer: Sendable {
    private let routes: [(prefix: String, status: Int, body: Data)]
    private let log = Mutex<[URL]>([])

    init(_ routes: [(prefix: String, status: Int, body: Data)]) {
        self.routes = routes
    }

    var requested: [String] { log.withLock { $0.map(\.absoluteString) } }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        log.withLock { $0.append(url) }
        guard let route = routes.first(where: { url.absoluteString.hasPrefix($0.prefix) }) else {
            throw URLError(.cannotConnectToHost)
        }
        return (route.body, HTTPURLResponse(url: url, statusCode: route.status, httpVersion: nil, headerFields: nil)!)
    }
}

struct StatusServiceTests {
    private static let pushURL = URL(string: "https://push.example")!
    private static let mainframe = URL(string: "https://status.mainframe.io/api/spaceInfo")!

    private static func service(push: FakeServer?, direct: FakeServer) -> StatusService {
        StatusService(
            spacePush: push.map { server in SpacePushClient(baseURL: pushURL) { try await server.load($0) } },
            direct: StatusClient { try await direct.load($0) }
        )
    }

    @Test func readsSpaceThroughSpacePush() async throws {
        let push = FakeServer([("https://push.example/v1/spaces", 200, try Fixture.data("mainframe-spaceinfo"))])
        let direct = FakeServer([])

        let info = try await Self.service(push: push, direct: direct).space(at: Self.mainframe)

        #expect(info.name == "Mainframe")
        #expect(push.requested == ["https://push.example/v1/spaces?endpoint=https%3A%2F%2Fstatus.mainframe.io%2Fapi%2FspaceInfo"])
        #expect(direct.requested.isEmpty)
    }

    @Test func fallsBackWhenSpacePushIsUnreachable() async throws {
        let push = FakeServer([])
        let direct = FakeServer([(Self.mainframe.absoluteString, 200, try Fixture.data("mainframe-spaceinfo"))])

        let info = try await Self.service(push: push, direct: direct).space(at: Self.mainframe)

        #expect(info.name == "Mainframe")
        #expect(push.requested.count == 1)
        #expect(direct.requested == [Self.mainframe.absoluteString])
    }

    @Test func fallsBackOverHTTPSForHTTPEndpoints() async throws {
        let endpoint = URL(string: "http://space.example/spaceapi.json")!
        let push = FakeServer([])
        let direct = FakeServer([("https://space.example/spaceapi.json", 200, try Fixture.data("mainframe-spaceinfo"))])

        let info = try await Self.service(push: push, direct: direct).space(at: endpoint)

        #expect(info.name == "Mainframe")
        // SpacePush gets the endpoint as listed; only the direct read is upgraded.
        #expect(push.requested == ["https://push.example/v1/spaces?endpoint=http%3A%2F%2Fspace.example%2Fspaceapi.json"])
        #expect(direct.requested == ["https://space.example/spaceapi.json"])
    }

    @Test func securesOnlyPlainHTTP() {
        #expect(StatusService.secure(URL(string: "http://a.example:80/x?y=1")!).absoluteString == "https://a.example/x?y=1")
        #expect(StatusService.secure(URL(string: "HTTP://a.example:8080/x")!).absoluteString == "https://a.example:8080/x")
        #expect(StatusService.secure(URL(string: "https://a.example/x")!).absoluteString == "https://a.example/x")
    }

    @Test(arguments: [404, 502, 503])
    func fallsBackOnErrorStatus(status: Int) async throws {
        let push = FakeServer([("https://push.example/", status, Data(#"{"error":"x"}"#.utf8))])
        let direct = FakeServer([(Self.mainframe.absoluteString, 200, try Fixture.data("mainframe-spaceinfo"))])

        let info = try await Self.service(push: push, direct: direct).space(at: Self.mainframe)

        #expect(info.name == "Mainframe")
    }

    @Test func readsDirectlyWithoutSpacePush() async throws {
        let direct = FakeServer([("https://api.spaceapi.io/", 200, try Fixture.data("aggregator"))])

        let entries = try await Self.service(push: nil, direct: direct).directory()

        #expect(entries.count == 7)
        #expect(direct.requested == ["https://api.spaceapi.io/"])
    }

    @Test func readsDirectoryAndRoomsThroughSpacePush() async throws {
        let push = FakeServer([
            ("https://push.example/v1/directory", 200, try Fixture.data("aggregator")),
            ("https://push.example/v1/mainframe/rooms", 200, try Fixture.data("mainframe-openstate")),
        ])
        let service = Self.service(push: push, direct: FakeServer([]))

        #expect(try await service.directory().count == 7)
        #expect(try await service.mainframeRooms().map(\.id) == ["space", "radstelle", "lab3d", "machining"])
    }

    @Test func reportsDirectFailureWhenBothFail() async {
        let service = Self.service(push: FakeServer([]), direct: FakeServer([]))

        await #expect(throws: URLError.self) {
            try await service.space(at: Self.mainframe)
        }
    }

    @Test func encodesEndpointStrictly() async throws {
        let push = FakeServer([("https://push.example/v1/spaces", 200, Data(#"{"space":"A"}"#.utf8))])
        let odd = try #require(URL(string: "https://a.example/status.json?x=1&y=a+b"))

        _ = try await Self.service(push: push, direct: FakeServer([])).space(at: odd)

        #expect(push.requested == ["https://push.example/v1/spaces?endpoint=https%3A%2F%2Fa.example%2Fstatus.json%3Fx%3D1%26y%3Da%2Bb"])
    }
}
