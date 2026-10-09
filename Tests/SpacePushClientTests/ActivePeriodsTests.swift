import Foundation
import Synchronization
import Testing
@testable import SpacePushClient

private final class Clock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 0))

    var now: Date { date.withLock { $0 } }

    func set(_ iso: String) {
        let parsed = try! Date.ISO8601FormatStyle().parse(iso)
        date.withLock { $0 = parsed }
    }
}

private final class Saved: Sendable {
    private let labels = Mutex<ActivePeriods.Labels?>(nil)

    var last: ActivePeriods.Labels? { labels.withLock { $0 } }

    func store(_ new: ActivePeriods.Labels) {
        labels.withLock { $0 = new }
    }
}

struct ActivePeriodsTests {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func periods(clock: Clock, saved: Saved = Saved(), reported: ActivePeriods.Labels = [:]) -> ActivePeriods {
        ActivePeriods(reported: reported, save: saved.store, now: { clock.now }, calendar: utc)
    }

    @Test func labelsUseISOWeeks() {
        let clock = Clock()
        let periods = Self.periods(clock: clock)
        // 2027-01-03 is a Sunday in ISO week 53 of 2026.
        let labels = periods.labels(for: try! Date.ISO8601FormatStyle().parse("2027-01-03T12:00:00Z"))
        #expect(labels == [.day: "2027-01-03", .week: "2026-W53", .month: "2027-01"])
    }

    @Test func reportsEachPeriodOnce() throws {
        let clock = Clock()
        clock.set("2026-10-09T10:00:00Z")
        let saved = Saved()
        let periods = Self.periods(clock: clock, saved: saved)

        let first = try #require(periods.begin())
        #expect(first.value == "day, week, month")
        periods.finish(first, delivered: true)
        #expect(saved.last == ["day": "2026-10-09", "week": "2026-W41", "month": "2026-10"])
        #expect(periods.begin() == nil)

        clock.set("2026-10-10T08:00:00Z")
        #expect(periods.begin()?.value == "day")

        // Monday opens a new week, and November a new month.
        let restarted = Self.periods(clock: clock, reported: try #require(saved.last))
        clock.set("2026-11-02T08:00:00Z")
        #expect(restarted.begin()?.value == "day, week, month")
    }

    @Test func concurrentRequestsReportOnce() throws {
        let clock = Clock()
        clock.set("2026-10-09T10:00:00Z")
        let periods = Self.periods(clock: clock)

        let first = try #require(periods.begin())
        #expect(periods.begin() == nil)
        periods.finish(first, delivered: false)
        #expect(periods.begin()?.value == "day, week, month")
    }
}
