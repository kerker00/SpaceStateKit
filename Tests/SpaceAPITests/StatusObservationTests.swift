import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import SpaceAPI

struct StatusObservationTests {
    private static let receipt = Date(timeIntervalSince1970: 1000)

    @Test func retainedOpeningExpiresWithoutAnotherRead() {
        let timing = ObservationTiming(source: .spacePush, observedAt: Date(timeIntervalSince1970: 900),
                                       receivedAt: Self.receipt, maximumAge: 200)
        #expect(timing.currentStatus(.open, at: Self.receipt) == .open)
        #expect(timing.freshness(at: Date(timeIntervalSince1970: 1099.999)) == .current)
        #expect(timing.freshness(at: Date(timeIntervalSince1970: 1100)) == .stale)
        #expect(timing.currentStatus(.open, at: Date(timeIntervalSince1970: 1200)) == .unknown)
        #expect(timing.currentStatus(.closed, at: Date(timeIntervalSince1970: 1200)) == .unknown)
    }

    @Test func missingFutureAndInvalidEvidenceRemainUnknown() {
        let timings = [
            ObservationTiming(source: .aggregator, observedAt: nil, receivedAt: Self.receipt),
            ObservationTiming(source: .aggregator, observedAt: Date(timeIntervalSince1970: 1001), receivedAt: Self.receipt),
            ObservationTiming(source: .direct, observedAt: Self.receipt, receivedAt: Self.receipt, maximumAge: 0),
            ObservationTiming(source: .direct, observedAt: Self.receipt, receivedAt: Self.receipt, maximumAge: -.infinity),
            ObservationTiming(source: .direct, observedAt: Date(timeIntervalSince1970: .nan), receivedAt: Self.receipt),
            ObservationTiming(source: .direct, observedAt: Self.receipt, receivedAt: Self.receipt,
                              advertisedExpiresAt: Date(timeIntervalSince1970: 999)),
        ]
        for timing in timings {
            #expect(timing.freshness(at: Self.receipt) == .unknown)
            // A timestamp that was future at receipt cannot turn into evidence later.
            #expect(timing.freshness(at: Date(timeIntervalSince1970: 1100)) == .unknown)
            #expect(timing.currentStatus(.open, at: Self.receipt) == .unknown)
        }
        let valid = ObservationTiming(source: .direct, observedAt: Self.receipt, receivedAt: Self.receipt)
        #expect(valid.freshness(at: Date(timeIntervalSince1970: 999)) == .unknown)
    }

    @Test func advertisedExpiryCanOnlyShortenTheLimit() {
        let earlier = ObservationTiming(source: .spacePush, observedAt: Self.receipt, receivedAt: Self.receipt,
            maximumAge: 900, advertisedExpiresAt: Date(timeIntervalSince1970: 1100))
        let later = ObservationTiming(source: .spacePush, observedAt: Self.receipt, receivedAt: Self.receipt,
            maximumAge: 900, advertisedExpiresAt: Date(timeIntervalSince1970: 3000))
        #expect(earlier.expiresAt == Date(timeIntervalSince1970: 1100))
        #expect(later.expiresAt == Date(timeIntervalSince1970: 1900))
        #expect(earlier.freshness(at: Date(timeIntervalSince1970: 1100)) == .stale)
    }

    @Test func currentObservationDoesNotTurnUnknownIntoClosed() {
        let timing = ObservationTiming(source: .direct, observedAt: Self.receipt, receivedAt: Self.receipt)
        #expect(timing.currentStatus(.unknown, at: Self.receipt) == .unknown)
    }

    @Test func directReadUsesReceiptRatherThanStateChange() async throws {
        let body = Data(#"{"space":"A","state":{"open":true,"lastchange":1}}"#.utf8)
        let client = Self.client(body: body)
        let observation = try await client.spaceObservation(at: URL(string: "https://space.example/api")!)
        #expect(observation.value.state?.lastChange == Date(timeIntervalSince1970: 1))
        #expect(observation.timing.observedAt == Self.receipt)
        #expect(observation.timing.receivedAt == Self.receipt)
        #expect(observation.timing.source == .direct)
        #expect(observation.timing.currentStatus(observation.value.status, at: Self.receipt) == .open)
    }

    @Test func directoryReceiptDoesNotRestampMissingOrOldEntries() async throws {
        let body = Data(#"[{"url":"https://a.example","lastSeen":990,"data":{"space":"A","state":{"open":true}}},{"url":"https://b.example","lastSeen":99,"data":{"space":"B","state":{"open":true}}},{"url":"https://c.example","data":{"space":"C","state":{"open":false}}},{"url":"https://d.example","lastSeen":1001,"data":{"space":"D","state":{"open":true}}}]"#.utf8)
        let entries = try await Self.client(body: body).directoryObservations()
        #expect(entries.map { $0.timing.freshness(at: Self.receipt) } == [.current, .stale, .unknown, .unknown])
        #expect(entries.map { $0.timing.currentStatus($0.value.info.status, at: Self.receipt) } == [.open, .unknown, .unknown, .unknown])
        #expect(entries[2].timing.observedAt == nil)
        #expect(entries.allSatisfy { $0.timing.receivedAt == Self.receipt && $0.timing.source == .aggregator })
        #expect(entries[1].value.info.status == .open) // Last known payload remains available.
    }

    private static func client(body: Data) -> StatusClient {
        StatusClient(now: { Self.receipt }) { request in
            (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func explicitDirectoryFailurePreservesDetailsWithoutCurrentOpening() async throws {
        let body = Data(#"[{"url":"https://a.example","lastSeen":990,"validationResult":{"reachable":false,"valid":"broken optional field"},"data":{"space":"A","state":{"open":true}}},{"url":"https://b.example","lastSeen":990,"validationResult":{"reachable":"invalid"},"data":{"space":"B","state":{"open":false}}}]"#.utf8)
        let entries = try await Self.client(body: body).directoryObservations()
        #expect(entries.count == 2)
        #expect(entries[0].value.reachable == false)
        #expect(entries[0].value.info.status == .open)
        #expect(entries[0].timing.observedAt == Date(timeIntervalSince1970: 990))
        #expect(entries[0].timing.freshness(at: Self.receipt) == .unknown)
        #expect(entries[0].timing.currentStatus(.open, at: Self.receipt) == .unknown)
        #expect(entries[1].value.reachable == nil)
        #expect(entries[1].timing.currentStatus(.closed, at: Self.receipt) == .closed)
    }
}
