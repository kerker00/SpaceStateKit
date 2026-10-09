import Foundation
import Synchronization

/// Lets SpacePush count active installs without telling them apart: the first request
/// of each day, ISO week and month names the periods it opens in `X-SpaceState-First`,
/// such as `day, week, month`. Only the labels of the periods already reported are kept,
/// on the device.
public final class ActivePeriods: Sendable {
    public enum Period: String, Sendable, CaseIterable {
        case day, week, month
    }

    /// The periods one request reports; pass it back to `finish(_:delivered:)`.
    public struct Report: Sendable, Equatable {
        /// The header value, e.g. `day, week`.
        public let value: String
        fileprivate let labels: [Period: String]
    }

    public typealias Labels = [String: String]

    private struct State {
        var reported: Labels
        var pending: Set<Period> = []
    }

    private let state: Mutex<State>
    private let save: @Sendable (Labels) -> Void
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    /// - Parameters:
    ///   - reported: The labels saved last time, by period name.
    ///   - save: Stores the labels after a report reached SpacePush.
    public init(
        reported: Labels,
        save: @escaping @Sendable (Labels) -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.state = Mutex(State(reported: reported))
        self.save = save
        self.now = now
        self.calendar = calendar
    }

    /// Kept in the standard user defaults under `key`.
    public static func userDefaults(key: String = "reportedPeriods") -> ActivePeriods {
        ActivePeriods(
            reported: UserDefaults.standard.dictionary(forKey: key) as? Labels ?? [:],
            save: { UserDefaults.standard.set($0, forKey: key) }
        )
    }

    /// The periods not reported yet, or nil. Requests running at the same time do not report them again.
    public func begin() -> Report? {
        let current = labels(for: now())
        return state.withLock { state in
            let open = Period.allCases.filter { state.reported[$0.rawValue] != current[$0] && !state.pending.contains($0) }
            guard !open.isEmpty else { return nil }
            state.pending.formUnion(open)
            return Report(
                value: open.map(\.rawValue).joined(separator: ", "),
                labels: current.filter { open.contains($0.key) }
            )
        }
    }

    /// Marks the report's periods as reported when SpacePush answered, or opens them again.
    public func finish(_ report: Report?, delivered: Bool) {
        guard let report else { return }
        let saved: Labels? = state.withLock { state in
            state.pending.subtract(report.labels.keys)
            guard delivered else { return nil }
            for (period, label) in report.labels {
                state.reported[period.rawValue] = label
            }
            return state.reported
        }
        if let saved {
            save(saved)
        }
    }

    /// `2026-10-09`, `2026-W41` and `2026-10` in the device's time zone.
    func labels(for date: Date) -> [Period: String] {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let week = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return [
            .day: String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!),
            .week: String(format: "%04d-W%02d", week.yearForWeekOfYear!, week.weekOfYear!),
            .month: String(format: "%04d-%02d", day.year!, day.month!),
        ]
    }
}
