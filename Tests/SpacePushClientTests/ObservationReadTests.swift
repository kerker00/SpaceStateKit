import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
import MainframeStatus
import SpaceAPI
import SpacePushClient

private final class ObservationServer: Sendable {
    enum Failure: Sendable { case cancelled, unreachable }
    let body: Data
    let headers: [String: String]
    let failure: Failure?
    private let log = Mutex<[URL]>([])
    var requested: [URL] { log.withLock { $0 } }

    init(body: Data = Data(#"{"space":"A","state":{"open":true,"lastchange":1}}"#.utf8),
         headers: [String: String] = [:], failure: Failure? = nil) {
        self.body = body
        self.headers = headers
        self.failure = failure
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        log.withLock { $0.append(request.url!) }
        switch failure {
        case .cancelled: throw CancellationError()
        case .unreachable: throw URLError(.cannotConnectToHost)
        case nil: break
        }
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
    }
}

struct ObservationReadTests {
    private static let receipt = Date(timeIntervalSince1970: 1000)
    private static let endpoint = URL(string: "https://space.example/api")!
    private static let policy = ["X-SpacePush-Fetched-At": "900", "X-SpacePush-Max-Data-Age": "200",
                                 "X-SpacePush-Expires-At": "1100"]
    private static let rooms = Data(#"{"space":{"state":"open","timestamp":1}}"#.utf8)
    private static let unusable: [[String: String]] = [
        [:], ["X-SpacePush-Fetched-At": "not a timestamp"],
        ["X-SpacePush-Fetched-At": "1001"], ["X-SpacePush-Fetched-At": "99"],
        ["X-SpacePush-Fetched-At": "999", "X-SpacePush-Max-Data-Age": "nan"],
        ["X-SpacePush-Fetched-At": "999", "X-SpacePush-Expires-At": "invalid"],
        ["X-SpacePush-Fetched-At": "999", "X-SpacePush-Expires-At": "998"],
        ["X-SpacePush-Fetched-At": "99999999999999999999999999999"],
    ]

    private static func proxy(_ server: ObservationServer) -> SpacePushClient {
        SpacePushClient(baseURL: URL(string: "https://push.example")!, now: { Self.receipt }) {
            try await server.load($0)
        }
    }

    private static func service(_ push: ObservationServer, _ direct: ObservationServer) -> StatusService {
        StatusService(spacePush: proxy(push), direct: StatusClient(now: { Self.receipt }) { try await direct.load($0) })
    }

    @Test func cachedSpacePreservesProxyEvidenceAndExpiresLocally() async throws {
        let observation = try await Self.proxy(ObservationServer(headers: Self.policy)).spaceObservation(at: Self.endpoint)
        #expect(observation.timing.source == .spacePush)
        #expect(observation.timing.observedAt == Date(timeIntervalSince1970: 900))
        #expect(observation.timing.receivedAt == Self.receipt)
        #expect(observation.timing.expiresAt == Date(timeIntervalSince1970: 1100))
        #expect(observation.value.state?.lastChange == Date(timeIntervalSince1970: 1))
        #expect(observation.timing.currentStatus(observation.value.status, at: Date(timeIntervalSince1970: 1100)) == .unknown)
    }

    @Test func roomsUseDocumentObservationRatherThanSince() async throws {
        let proxy = Self.proxy(ObservationServer(body: Self.rooms, headers: Self.policy))
        let rooms = try await proxy.mainframeRoomsObservation()
        #expect(rooms.value.first?.since == Date(timeIntervalSince1970: 1))
        #expect(rooms.timing.observedAt == Date(timeIntervalSince1970: 900))
        #expect(rooms.timing.freshness(at: Self.receipt) == .current)
        #expect(rooms.timing.currentStatus(rooms.value[0].state.status, at: Date(timeIntervalSince1970: 1100)) == .unknown)
    }

    @Test(arguments: unusable)
    func unprovenProxyPayloadDoesNotSupplyCurrentStatus(headers: [String: String]) async throws {
        let observation = try await Self.proxy(ObservationServer(headers: headers)).spaceObservation(at: Self.endpoint)
        #expect(observation.value.status == .open)
        #expect(observation.timing.currentStatus(.open, at: Self.receipt) == .unknown)
    }

    @Test func olderProxyWithOnlyFetchHeaderUsesConservativeDefault() async throws {
        let observation = try await Self.proxy(ObservationServer(headers: ["X-SpacePush-Fetched-At": "900"]))
            .spaceObservation(at: Self.endpoint)
        #expect(observation.timing.maximumAge == 900)
        #expect(observation.timing.expiresAt == Date(timeIntervalSince1970: 1800))
        #expect(observation.timing.freshness(at: Self.receipt) == .current)
    }

    @Test func proxyDirectoryUsesEntryTimesAndConfiguredPolicy() async throws {
        let body = Data(#"[{"url":"https://a.example","lastSeen":900,"data":{"space":"A","state":{"open":true}}},{"url":"https://b.example","lastSeen":799,"data":{"space":"B","state":{"open":true}}},{"url":"https://c.example","data":{"space":"C","state":{"open":false}}}]"#.utf8)
        let server = ObservationServer(body: body, headers: ["X-SpacePush-Max-Data-Age": "200"])
        let entries = try await Self.proxy(server).directoryObservations()
        #expect(entries.map { $0.timing.freshness(at: Self.receipt) } == [.current, .stale, .unknown])
        #expect(entries.allSatisfy { $0.timing.source == .spacePush && $0.timing.receivedAt == Self.receipt })
        #expect(entries[2].timing.observedAt == nil)
        let broken = ObservationServer(body: body, headers: ["X-SpacePush-Max-Data-Age": "invalid"])
        #expect(try await Self.proxy(broken).directoryObservations().allSatisfy {
            $0.timing.currentStatus($0.value.info.status, at: Self.receipt) == .unknown
        })
    }

    @Test(arguments: unusable)
    func serviceFallsBackForUnprovenProxyEvidence(headers: [String: String]) async throws {
        let push = ObservationServer(headers: headers)
        let direct = ObservationServer()
        let endpoint = URL(string: "http://space.example:80/api")!
        let observation = try await Self.service(push, direct).spaceObservation(at: endpoint)
        #expect(observation.timing.source == .direct)
        #expect(observation.timing.observedAt == Self.receipt)
        #expect(direct.requested == [Self.endpoint])
        #expect(push.requested.count == 1)
    }

    @Test func serviceKeepsCurrentProxyWithoutFallback() async throws {
        let direct = ObservationServer(failure: .unreachable)
        let observation = try await Self.service(ObservationServer(headers: Self.policy), direct).spaceObservation(at: Self.endpoint)
        #expect(observation.timing.observedAt == Date(timeIntervalSince1970: 900))
        #expect(direct.requested.isEmpty)
    }

    @Test func staleRoomsUseDirectDocumentReceipt() async throws {
        let push = ObservationServer(body: Self.rooms, headers: ["X-SpacePush-Fetched-At": "99"])
        let direct = ObservationServer(body: Self.rooms)
        let observation = try await Self.service(push, direct).mainframeRoomsObservation()
        #expect(observation.timing.source == .direct)
        #expect(observation.timing.observedAt == Self.receipt)
        #expect(observation.value[0].since == Date(timeIntervalSince1970: 1))
        #expect(direct.requested == [Mainframe.openStateURL])
    }

    @Test func observationCancellationDoesNotStartFallback() async throws {
        let direct = ObservationServer()
        let service = Self.service(ObservationServer(failure: .cancelled), direct)
        await #expect(throws: CancellationError.self) { try await service.spaceObservation(at: Self.endpoint) }
        await #expect(throws: CancellationError.self) { try await service.mainframeRoomsObservation() }
        await #expect(throws: CancellationError.self) { try await service.directoryObservations() }
        #expect(direct.requested.isEmpty)
    }

    @Test func invalidEndpointDoesNotReachObservationLoaders() async throws {
        let push = ObservationServer(headers: Self.policy)
        let direct = ObservationServer()
        let endpoint = URL(string: "https://user:secret@space.example/api")!
        await #expect(throws: EndpointValidationError.invalidEndpoint) {
            try await Self.service(push, direct).spaceObservation(at: endpoint)
        }
        #expect(push.requested.isEmpty)
        #expect(direct.requested.isEmpty)
    }

    @Test func failedFallbackRemainsAnErrorWithoutSuccessTiming() async throws {
        let service = Self.service(ObservationServer(), ObservationServer(failure: .unreachable))
        await #expect(throws: URLError.self) { try await service.spaceObservation(at: Self.endpoint) }
    }
}
