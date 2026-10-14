package net.grafixmafia.spacestatekit

import java.time.Instant

/** The read path, not a guarantee of a new physical measurement. */
enum class ObservationSource { DIRECT, AGGREGATOR, SPACE_PUSH, UNKNOWN }

enum class ObservationFreshness { CURRENT, STALE, UNKNOWN }

/** Original source evidence, retained unchanged on display or failed attempts. */
data class ObservationTiming(
    val source: ObservationSource,
    val observedAt: Instant?,
    val receivedAt: Instant?,
    val expiresAt: Instant?,
) {
    fun freshness(at: Instant = Instant.now()): ObservationFreshness {
        val observed = observedAt ?: return ObservationFreshness.UNKNOWN
        val received = receivedAt ?: return ObservationFreshness.UNKNOWN
        val expiry = expiresAt ?: return ObservationFreshness.UNKNOWN
        if (source == ObservationSource.UNKNOWN || observed > received || expiry < observed || at < received) {
            return ObservationFreshness.UNKNOWN
        }
        return if (at < expiry) ObservationFreshness.CURRENT else ObservationFreshness.STALE
    }

    fun currentStatus(reported: SpaceStatus, at: Instant = Instant.now()): SpaceStatus =
        if (freshness(at) == ObservationFreshness.CURRENT) reported else SpaceStatus.UNKNOWN
}

/** The reported value is retained; callers evaluate timing before showing its status. */
data class StatusObservation<T>(val value: T, val timing: ObservationTiming)
