import Foundation

/// Where the client obtained a document. This describes the read path, not a
/// guarantee that the provider freshly measured a physical door or sensor.
public enum ObservationSource: String, Sendable, Hashable {
    case direct
    case aggregator
    case spacePush
}

public enum ObservationFreshness: String, Sendable, Hashable {
    case current
    case stale
    case unknown
}

/// Successful observation and client receipt times, separate from state changes.
public struct ObservationTiming: Sendable, Hashable {
    public static let defaultMaximumAge: TimeInterval = 900

    public let source: ObservationSource
    /// Successful endpoint fetch or directory `lastSeen`; nil means no evidence.
    public let observedAt: Date?
    /// When the client successfully received this answer, never a failed attempt.
    public let receivedAt: Date
    public let maximumAge: TimeInterval
    /// An optional earlier expiry advertised by a proxy.
    public let advertisedExpiresAt: Date?
    /// An explicit directory reachability result; absence supplies no extra claim.
    public let sourceReachable: Bool?

    public init(source: ObservationSource, observedAt: Date?, receivedAt: Date,
                maximumAge: TimeInterval = Self.defaultMaximumAge, advertisedExpiresAt: Date? = nil,
                sourceReachable: Bool? = nil) {
        self.source = source
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.maximumAge = maximumAge
        self.advertisedExpiresAt = advertisedExpiresAt
        self.sourceReachable = sourceReachable
    }

    /// Nil for missing, nonfinite, future-at-receipt or otherwise invalid timing.
    /// A later advertised expiry never extends the configured observation limit.
    public var expiresAt: Date? {
        guard sourceReachable != false, let observedAt,
              observedAt.timeIntervalSince1970.isFinite,
              receivedAt.timeIntervalSince1970.isFinite,
              observedAt <= receivedAt,
              maximumAge.isFinite, maximumAge > 0 else { return nil }
        let limit = observedAt.addingTimeInterval(maximumAge)
        guard limit.timeIntervalSince1970.isFinite else { return nil }
        if let advertisedExpiresAt {
            guard advertisedExpiresAt.timeIntervalSince1970.isFinite,
                  advertisedExpiresAt >= observedAt else { return nil }
            return min(limit, advertisedExpiresAt)
        }
        return limit
    }

    /// Evaluate again when displaying retained data: a receipt does not stay fresh
    /// indefinitely. Expiry is exclusive; a backwards client clock is unknown.
    public func freshness(at date: Date = Date()) -> ObservationFreshness {
        guard date.timeIntervalSince1970.isFinite, date >= receivedAt,
              let expiresAt else { return .unknown }
        return date < expiresAt ? .current : .stale
    }

    /// Stale or unproven data can remain available as a labelled last known value,
    /// but cannot provide a current open/closed state.
    public func currentStatus(_ reported: SpaceStatus, at date: Date = Date()) -> SpaceStatus {
        freshness(at: date) == .current ? reported : .unknown
    }
}

/// A decoded value and the evidence for its observation age. `value` is retained
/// unchanged; use its timing before presenting an open/closed state as current.
public struct StatusObservation<Value: Sendable>: Sendable {
    public let value: Value
    public let timing: ObservationTiming

    public init(value: Value, timing: ObservationTiming) {
        self.value = value
        self.timing = timing
    }
}
