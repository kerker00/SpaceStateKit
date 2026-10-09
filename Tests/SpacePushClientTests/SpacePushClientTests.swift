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
