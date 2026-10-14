import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MainframeStatus
import SpaceAPI
import SpacePushClient
import Synchronization
import Testing
@testable import SpaceStateAndroidFacade

struct AndroidObservationTests {
    private static let receipt = Date(timeIntervalSince1970: 1000)
    private static let endpoint = "https://space.example/api"
    private static let spaceBody = #"{"space":"A","state":{"open":true,"lastchange":1,"message":"Welcome"}}"#
    private static let roomBody = #"{"space":{"state":"open+","timestamp":1},"radstelle":{"state":"closing","timestamp":2}}"#
    private static let policy = ["X-SpacePush-Fetched-At": "900", "X-SpacePush-Max-Data-Age": "200", "X-SpacePush-Expires-At": "1075"]

    private static func direct(_ body: String = spaceBody, status: Int = 200, error: URLError? = nil) -> StatusClient {
        StatusClient(maximumObservationAge: 200, now: { receipt }, load: { request in
            if let error { throw error }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
    }

    private static func proxy(_ headers: [String: String] = policy, body: String = spaceBody) -> SpacePushClient {
        SpacePushClient(baseURL: URL(string: "https://push.example")!, now: { receipt }, load: { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        })
    }

    @Test func directSpaceExportsObservationReceiptAndStateChangeSeparately() async throws {
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: StatusClient(
            maximumObservationAge: 200, now: { Self.receipt }, load: { request in
                #expect(request.url?.absoluteString == Self.endpoint)
                return (Data(Self.spaceBody.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })))
        let result = try await service.spaceObservation(endpoint: "http://space.example/api")
        #expect(result.value.endpoint == "http://space.example/api")
        #expect(result.value.name == "A")
        #expect(result.value.status == .open)
        #expect(result.value.lastChange == 1)
        #expect(result.timing.source == "direct")
        #expect(result.timing.observedAt == 1000)
        #expect(result.timing.receivedAt == 1000)
        #expect(result.timing.expiresAt == 1200)
    }

    @Test func proxySpacePreservesOriginalHeaderEvidence() async throws {
        let service = SpaceStateService(service: StatusService(spacePush: Self.proxy(), direct: Self.direct(error: URLError(.cannotConnectToHost))))
        let result = try await service.spaceObservation(endpoint: Self.endpoint)
        #expect(result.timing.source == "spacePush")
        #expect(result.timing.observedAt == 900)
        #expect(result.timing.receivedAt == 1000)
        #expect(result.timing.expiresAt == 1075)
        #expect(result.value.lastChange == 1)
    }

    @Test func directoryExportsPerEntryEvidenceWithoutFillingMissingTimes() async throws {
        let body = #"[{"url":"https://fresh.example/api","lastSeen":990,"data":{"space":"Fresh","state":{"open":true}}},{"url":"https://missing.example/api","data":{"space":"Missing","state":{"open":false}}},{"url":"https://future.example/api","lastSeen":1001,"data":{"space":"Future","state":{"open":true}}},{"url":"https://stale.example/api","lastSeen":500,"data":{"space":"Stale","state":{"open":true}}},{"url":"https://unreachable.example/api","lastSeen":990,"validationResult":{"reachable":false},"data":{"space":"Unreachable","state":{"open":true}}}]"#
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: Self.direct(body)))
        let results = try await service.directoryObservations()
        let values = Dictionary(uniqueKeysWithValues: results.map { ($0.value.name, $0) })
        #expect(results.count == 5)
        #expect(values["Fresh"]?.timing.source == "aggregator")
        #expect(values["Fresh"]?.timing.observedAt == 990)
        #expect(values["Fresh"]?.timing.expiresAt == 1190)
        #expect(values["Missing"]?.timing.observedAt == nil)
        #expect(values["Missing"]?.timing.expiresAt == nil)
        #expect(values["Future"]?.timing.observedAt == nil)
        #expect(values["Future"]?.timing.expiresAt == nil)
        #expect(values["Stale"]?.timing.observedAt == 500)
        #expect(values["Stale"]?.timing.expiresAt == 700)
        #expect(values["Unreachable"]?.timing.observedAt == 990)
        #expect(values["Unreachable"]?.timing.expiresAt == nil)
        #expect(results.allSatisfy { $0.timing.receivedAt == 1000 })
    }

    @Test func roomDocumentObservationIsIndependentOfIndividualStateChanges() async throws {
        let service = SpaceStateService(service: StatusService(spacePush: Self.proxy(body: Self.roomBody), direct: Self.direct(error: URLError(.cannotConnectToHost))))
        let result = try await service.mainframeRoomsObservation()
        #expect(result.values.count == 2)
        #expect(result.values.first(where: { $0.id == "space" })?.since == 1)
        #expect(result.values.first(where: { $0.id == "space" })?.rawState == "open+")
        #expect(result.timing.observedAt == 900)
        #expect(result.timing.receivedAt == 1000)
        #expect(result.timing.expiresAt == 1075)
        let empty = ObservedRooms(StatusObservation(value: [MainframeRoom](), timing: ObservationTiming(source: .direct,
            observedAt: Self.receipt, receivedAt: Self.receipt)))
        #expect(empty.values.isEmpty)
        #expect(empty.timing.observedAt == 1000)
    }

    @Test func unprovenProxySpacesUseTheSharedDirectFallback() async throws {
        for headers in [[:], ["X-SpacePush-Fetched-At": "99"], ["X-SpacePush-Fetched-At": "1001"],
                        ["X-SpacePush-Fetched-At": "999", "X-SpacePush-Max-Data-Age": "bad"]] {
            let service = SpaceStateService(service: StatusService(spacePush: Self.proxy(headers), direct: Self.direct()))
            let result = try await service.spaceObservation(endpoint: Self.endpoint)
            #expect(result.timing.source == "direct")
            #expect(result.timing.observedAt == 1000)
            #expect(result.timing.expiresAt == 1200)
        }
    }

    @Test func malformedDirectoryPolicyKeepsNamesWithoutAnExpiry() async throws {
        let body = #"[{"url":"https://space.example/api","lastSeen":990,"data":{"space":"A","state":{"open":true}}}]"#
        let service = SpaceStateService(service: StatusService(spacePush: Self.proxy(["X-SpacePush-Max-Data-Age": "bad"], body: body),
                                                              direct: Self.direct(error: URLError(.cannotConnectToHost))))
        let values = try await service.directoryObservations()
        #expect(values.count == 1)
        #expect(values[0].value.name == "A")
        #expect(values[0].timing.source == "spacePush")
        #expect(values[0].timing.observedAt == 990)
        #expect(values[0].timing.receivedAt == 1000)
        #expect(values[0].timing.expiresAt == nil)
    }

    @Test func nonportableMissingAndFutureTimingNeverExportsUsableExpiry() {
        for observed: TimeInterval? in [nil, .nan, .infinity, -1, 1e300, 1001] {
            let timing = ReadTiming(ObservationTiming(source: .aggregator,
                observedAt: observed.map(Date.init(timeIntervalSince1970:)), receivedAt: Self.receipt))
            #expect(timing.observedAt == nil)
            #expect(timing.receivedAt == 1000)
            #expect(timing.expiresAt == nil)
        }
        let badReceipt = ReadTiming(ObservationTiming(source: .direct, observedAt: Self.receipt,
            receivedAt: Date(timeIntervalSince1970: 1e300)))
        #expect(badReceipt.receivedAt == nil)
        #expect(badReceipt.observedAt == nil)
        #expect(badReceipt.expiresAt == nil)
        let hugeAge = ReadTiming(ObservationTiming(source: .direct, observedAt: Self.receipt,
            receivedAt: Self.receipt, maximumAge: 1e300))
        #expect(hugeAge.observedAt == 1000)
        #expect(hugeAge.expiresAt == nil)
    }

    @Test func exportedExpiryCannotExtendPolicyAndUnreachableEvidenceStaysUnknown() {
        for (advertised, expected) in [(1050.0, 1050.0), (9999.0, 1100.0)] {
            let result = ReadTiming(ObservationTiming(source: .spacePush, observedAt: Date(timeIntervalSince1970: 900),
                receivedAt: Self.receipt, maximumAge: 200, advertisedExpiresAt: Date(timeIntervalSince1970: advertised)))
            #expect(result.expiresAt == expected)
        }
        let unreachable = ReadTiming(ObservationTiming(source: .aggregator, observedAt: Date(timeIntervalSince1970: 990),
            receivedAt: Self.receipt, sourceReachable: false))
        #expect(unreachable.observedAt == 990)
        #expect(unreachable.expiresAt == nil)
    }

    @Test func unusableOptionalStateDatesCannotOverflowAndroidDateConversion() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Data(#"{"space":"A","state":{"open":true,"lastchange":1e300}}"#.utf8))
        let value = Space(endpoint: Self.endpoint, info: info)
        #expect(value.name == "A")
        #expect(value.status == .open)
        #expect(value.lastChange == nil)
        let rooms = try Mainframe.decodeRooms(Data(#"{"space":{"state":"open","timestamp":1e300}}"#.utf8))
        #expect(Room(try #require(rooms.first)).since == nil)
    }

    @Test func observationCancellationIsPreservedAcrossAllEntryPoints() async {
        let calls = Mutex(0)
        let direct = StatusClient(now: { Self.receipt }, load: { _ in calls.withLock { $0 += 1 }; throw CancellationError() })
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: direct))
        await #expect(throws: CancellationError.self) { try await service.spaceObservation(endpoint: Self.endpoint) }
        await #expect(throws: CancellationError.self) { try await service.directoryObservations() }
        await #expect(throws: CancellationError.self) { try await service.mainframeRoomsObservation() }
        #expect(calls.withLock { $0 } == 3)
    }

    @Test func invalidConfigurationKeepsStableErrorsOnObservationReads() async {
        let service = SpaceStateService(spacePushURL: "https://user:secret@push.example", userAgent: "Test", activePeriodsFile: nil)
        for operation in [0, 1, 2] {
            do {
                switch operation {
                case 0: _ = try await service.spaceObservation(endpoint: Self.endpoint)
                case 1: _ = try await service.directoryObservations()
                default: _ = try await service.mainframeRoomsObservation()
                }
                Issue.record("Expected invalid configuration")
            } catch { #expect(String(describing: error) == "spacestatekit:invalidEndpoint") }
        }
    }

    @Test func invalidObservationEndpointsAreRejectedBeforeLoading() async {
        let calls = Mutex(0)
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: StatusClient { _ in
            calls.withLock { $0 += 1 }; throw URLError(.cannotConnectToHost)
        }))
        for endpoint in ["file:///tmp/space", "https://user:secret@space.example/api", "https://space.example/api\n"] {
            do { _ = try await service.spaceObservation(endpoint: endpoint); Issue.record("Expected invalid endpoint") }
            catch { #expect(String(describing: error) == "spacestatekit:invalidEndpoint") }
        }
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func existingValueOnlyMethodsRemainAvailableAndKeepReportedValues() async throws {
        let direct = StatusClient(now: { Self.receipt }, load: { request in
            let body = request.url == Mainframe.openStateURL ? Self.roomBody
                : request.url == SpaceDirectory.aggregatorURL ? #"[{"url":"https://space.example/api","data":{"space":"A","state":{"open":true}}}]"# : Self.spaceBody
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let service = SpaceStateService(service: StatusService(spacePush: nil, direct: direct))
        #expect(try await service.space(endpoint: Self.endpoint).status == .open)
        #expect(try await service.mainframeRooms().count == 2)
        #expect(try await service.directory().first?.status == .open)
        let observations = try await service.directoryObservations()
        #expect(observations.first?.value.status == .open)
        #expect(observations.first?.timing.observedAt == nil)
        #expect(observations.first?.timing.expiresAt == nil)
    }

    @Test func observationFailuresKeepStableErrorClassification() async {
        let cases: [(StatusClient, String)] = [
            (Self.direct(status: 503), "spacestatekit:http:503"),
            (Self.direct("not JSON"), "spacestatekit:invalidData"),
            (Self.direct(error: URLError(.timedOut)), "spacestatekit:timeout"),
            (Self.direct(error: URLError(.cannotConnectToHost)), "spacestatekit:unreachable"),
        ]
        for (direct, expected) in cases {
            let service = SpaceStateService(service: StatusService(spacePush: nil, direct: direct))
            do { _ = try await service.spaceObservation(endpoint: Self.endpoint); Issue.record("Expected failure") }
            catch { #expect(String(describing: error) == expected) }
        }
    }
}
