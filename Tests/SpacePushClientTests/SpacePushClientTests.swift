import Foundation
import Synchronization
import Testing
@testable import SpacePushClient

private final class RequestLog: Sendable {
    private let requests = Mutex<[URLRequest]>([])

    var all: [URLRequest] { requests.withLock { $0 } }

    func append(_ request: URLRequest) {
        requests.withLock { $0.append(request) }
    }
}

struct SpacePushClientTests {
    private static let baseURL = URL(string: "http://127.0.0.1:8080")!
    private static let token = Data([0x00, 0xab, 0x10, 0xff])
    private static let mainframe = URL(string: "https://status.mainframe.io/api/spaceInfo")!

    private static func client(status: Int = 204, body: Data = Data(), log: RequestLog = RequestLog()) -> SpacePushClient {
        SpacePushClient(baseURL: baseURL) { request in
            log.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (body, response)
        }
    }

    @Test func encodesTokenAsLowercaseHex() {
        #expect(SpacePushClient.hex(Self.token) == "00ab10ff")
    }

    @Test func registerSendsPutWithSubscriptions() async throws {
        let log = RequestLog()
        try await Self.client(log: log).register(
            deviceToken: Self.token,
            environment: .sandbox,
            subscriptions: [PushSubscription(endpoint: Self.mainframe), PushSubscription(endpoint: Self.mainframe, room: "radstelle")]
        )

        let request = try #require(log.all.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "http://127.0.0.1:8080/v1/devices/00ab10ff")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == """
            {"environment":"sandbox","subscriptions":[{"endpoint":"https://status.mainframe.io/api/spaceInfo"},\
            {"endpoint":"https://status.mainframe.io/api/spaceInfo","room":"radstelle"}]}
            """)
    }

    @Test func registerSendsPlatformWhenGiven() async throws {
        let log = RequestLog()
        try await Self.client(log: log).register(
            deviceToken: Self.token, environment: .production, subscriptions: [], platform: "macos"
        )

        let body = try #require(log.all.first?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"environment":"production","platform":"macos","subscriptions":[]}"#)
    }

    @Test func sendsConfiguredHeaders() async throws {
        let log = RequestLog()
        let headers = ["User-Agent": "SpaceState/2.0.0 (macOS 26.0)"]
        let client = SpacePushClient(baseURL: Self.baseURL, headers: headers) { request in
            log.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (Data("[]".utf8), response)
        }
        _ = try? await client.directory()
        try await client.unregister(deviceToken: Self.token)

        #expect(log.all.count == 2)
        for request in log.all {
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "SpaceState/2.0.0 (macOS 26.0)")
            #expect(request.value(forHTTPHeaderField: "X-SpaceState-First") == nil)
        }
    }

    @Test func reportsActivePeriodsOnceDelivered() async throws {
        let log = RequestLog()
        let periods = ActivePeriods(reported: [:], save: { _ in })
        let client = SpacePushClient(baseURL: Self.baseURL, activePeriods: periods) { request in
            log.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        // An error answer still reached SpacePush, which counted the request.
        _ = try? await client.mainframeRooms()
        _ = try? await client.mainframeRooms()

        #expect(log.all.map { $0.value(forHTTPHeaderField: "X-SpaceState-First") } == ["day, week, month", nil])
    }

    @Test func reportsActivePeriodsAgainAfterNetworkError() async throws {
        let log = RequestLog()
        let periods = ActivePeriods(reported: [:], save: { _ in })
        let failing = SpacePushClient(baseURL: Self.baseURL, activePeriods: periods) { request in
            log.append(request)
            throw URLError(.notConnectedToInternet)
        }
        _ = try? await failing.mainframeRooms()
        _ = try? await Self.client(log: log).mainframeRooms()
        let working = SpacePushClient(baseURL: Self.baseURL, activePeriods: periods) { request in
            log.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }
        _ = try? await working.mainframeRooms()

        #expect(log.all.map { $0.value(forHTTPHeaderField: "X-SpaceState-First") } == ["day, week, month", nil, "day, week, month"])
    }

    @Test func unregisterSendsDelete() async throws {
        let log = RequestLog()
        try await Self.client(log: log).unregister(deviceToken: Self.token)

        let request = try #require(log.all.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "http://127.0.0.1:8080/v1/devices/00ab10ff")
        #expect(request.httpBody == nil)
    }

    @Test func surfacesServiceError() async {
        let client = Self.client(status: 503, body: Data(#"{"error":"registry_full"}"#.utf8))

        await #expect(throws: SpacePushError.httpStatus(503, reason: "registry_full")) {
            try await client.register(deviceToken: Self.token, environment: .production, subscriptions: [])
        }
    }

    @Test func toleratesErrorWithoutBody() async {
        let client = Self.client(status: 502)

        await #expect(throws: SpacePushError.httpStatus(502, reason: nil)) {
            try await client.unregister(deviceToken: Self.token)
        }
    }
}
