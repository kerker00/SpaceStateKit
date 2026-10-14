package net.grafixmafia.spacestatekit

import java.time.Instant
import kotlin.math.floor
import net.grafixmafia.spacestatekit.bridge.ReadTiming as BridgeReadTiming
import java.util.Optional
import java.util.OptionalDouble
import java.util.concurrent.CompletableFuture
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.future.await
import net.grafixmafia.spacestatekit.bridge.SpaceStateService
import org.swift.swiftkit.core.SwiftArena
import net.grafixmafia.spacestatekit.bridge.DirectoryItem as BridgeDirectoryItem
import net.grafixmafia.spacestatekit.bridge.Room as BridgeRoom
import net.grafixmafia.spacestatekit.bridge.RoomState as BridgeRoomState
import net.grafixmafia.spacestatekit.bridge.Space as BridgeSpace
import net.grafixmafia.spacestatekit.bridge.SpaceDetails as BridgeSpaceDetails
import net.grafixmafia.spacestatekit.bridge.Status as BridgeStatus

/** The public open state of a space, as in SpaceStateKit's `SpaceStatus`. */
enum class SpaceStatus { OPEN, CLOSED, UNKNOWN }

data class SpaceInfo(
    val endpoint: String,
    val name: String,
    val status: SpaceStatus,
    val lastChange: Instant?,
    val message: String?,
    val website: String?,
    val logo: String?,
    val address: String?,
    val details: SpaceDetails = SpaceDetails(),
)

/** The states Mainframe's status server reports, as in SpaceStateKit's `MainframeRoomState`. */
enum class MainframeRoomState(val status: SpaceStatus) {
    CLOSED(SpaceStatus.CLOSED),
    KEYHOLDER(SpaceStatus.CLOSED),
    MEMBER(SpaceStatus.CLOSED),
    OPEN(SpaceStatus.OPEN),
    OPEN_PLUS(SpaceStatus.OPEN),
    CLOSING(SpaceStatus.CLOSED),
    UNKNOWN(SpaceStatus.UNKNOWN),
}

data class MainframeRoom(
    /** The status server's key, e.g. "space" or "radstelle"; also a push subscription's room. */
    val id: String,
    val name: String,
    val state: MainframeRoomState,
    /** The status server's value, shown for unknown states. */
    val rawState: String,
    val since: Instant?,
)

data class DirectoryEntry(
    val endpoint: String,
    val name: String,
    val address: String?,
    val status: SpaceStatus,
)

/** Why a read failed, so the app can explain it in its own language. */
sealed class SpaceStateException(message: String) : Exception(message) {
    /** No connection, or the host could not be found or reached. */
    class Unreachable : SpaceStateException("unreachable")
    class Timeout : SpaceStateException("timeout")
    class HttpStatus(val code: Int) : SpaceStateException("HTTP $code")
    class ResponseTooLarge : SpaceStateException("response too large")
    /** The answer was not a readable SpaceAPI document, directory or room list. */
    class InvalidData : SpaceStateException("invalid data")
    class InvalidEndpoint : SpaceStateException("invalid endpoint")
    class Other(detail: String) : SpaceStateException(detail)

    companion object {
        /** Reads the code the Swift facade puts into the exception's message. */
        internal fun from(error: Throwable): SpaceStateException {
            val code = error.message?.substringAfter("spacestatekit:", missingDelimiterValue = "")
                ?: return Other(error.toString())
            return when {
                code == "unreachable" -> Unreachable()
                code == "timeout" -> Timeout()
                code.startsWith("http:") -> code.removePrefix("http:").toIntOrNull()?.let(::HttpStatus) ?: Other(code)
                code == "tooLarge" -> ResponseTooLarge()
                code == "invalidData" -> InvalidData()
                code == "invalidEndpoint" -> InvalidEndpoint()
                code.startsWith("other:") -> Other(code.removePrefix("other:"))
                else -> Other(error.toString())
            }
        }
    }
}

/**
 * SpaceStateKit's `StatusService` for Kotlin: reads through SpacePush and falls back to
 * the spaces directly. Every call runs in Swift; failures surface as [SpaceStateException].
 *
 * @param spacePushUrl SpacePush's base URL; null reads every space directly.
 * @param userAgent Sent to SpacePush, e.g. `SpaceState/1.0 (Android 16)`.
 * @param activePeriodsFile Where reported day, week and month labels are kept; null reports none.
 */
class SpaceStateClient(spacePushUrl: String?, userAgent: String, activePeriodsFile: String?) {
    // Swift objects are released once Java no longer references them.
    private val arena = SwiftArena.ofAuto()
    private val service = SpaceStateService.init(
        Optional.ofNullable(spacePushUrl), userAgent, Optional.ofNullable(activePeriodsFile), arena,
    )

    suspend fun space(endpoint: String): SpaceInfo = call { service.space(endpoint, arena) }.toKotlin()

    suspend fun mainframeRooms(): List<MainframeRoom> = call { service.mainframeRooms(arena) }.map { it.toKotlin() }

    suspend fun directory(): List<DirectoryEntry> = call { service.directory(arena) }.map { it.toKotlin() }

    /** Additive reads preserve original evidence; no missing timestamp is filled with now. */
    suspend fun spaceObservation(endpoint: String): StatusObservation<SpaceInfo> {
        val observation = call { service.spaceObservation(endpoint, arena) }
        return StatusObservation(observation.getValue(arena).toKotlin(), observation.getTiming(arena).toKotlin())
    }

    suspend fun mainframeRoomsObservation(): StatusObservation<List<MainframeRoom>> {
        val observation = call { service.mainframeRoomsObservation(arena) }
        return StatusObservation(observation.getValues(arena).map { it.toKotlin() }, observation.getTiming(arena).toKotlin())
    }

    suspend fun directoryObservations(): List<StatusObservation<DirectoryEntry>> =
        call { service.directoryObservations(arena) }.map { observation ->
            StatusObservation(observation.getValue(arena).toKotlin(), observation.getTiming(arena).toKotlin())
        }

    private suspend fun <T> call(start: () -> CompletableFuture<T>): T = try {
        // SpaceStateKit gives up after 15 seconds. Right after a network change, a request on
        // Android was seen to hang well past that; the deadline keeps it from blocking the next.
        withTimeout(CALL_TIMEOUT_MILLIS) { start().await() }
    } catch (_: TimeoutCancellationException) {
        throw SpaceStateException.Timeout()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        throw SpaceStateException.from(e)
    }

    companion object {
        private const val CALL_TIMEOUT_MILLIS = 30_000L

        val mainframeEndpoint: String get() = SpaceStateService.getMainframeEndpoint()

        fun isMainframe(endpoint: String): Boolean = SpaceStateService.isMainframe(endpoint)
    }

    private fun BridgeSpace.toKotlin() = SpaceInfo(
        endpoint = endpoint,
        name = name,
        status = getStatus(arena).toKotlin(),
        lastChange = lastChange.toInstant(),
        message = message.orElse(null),
        website = website.orElse(null),
        logo = logo.orElse(null),
        address = address.orElse(null),
        details = getDetails(arena).toKotlin(),
    )

    private fun BridgeSpaceDetails.toKotlin() = SpaceDetails(
        accessHint = accessHint.orElse(null), countryCode = countryCode.orElse(null),
        timezone = timezone.orElse(null),
        latitude = latitude.toNumber(), longitude = longitude.toNumber(),
        contacts = getContacts(arena).map { DetailContact(it.kind, it.value) },
        keyholders = getKeyholders(arena).map { person ->
            DetailKeyholder(person.name.orElse(null), person.ircNick.orElse(null),
                person.getContacts(arena).map { DetailContact(it.kind, it.value) })
        },
        feeds = getFeeds(arena).map { DetailFeed(it.kind, it.url, it.format.orElse(null)) },
        projects = getProjects().toList(),
        links = getLinks(arena).map { DetailLink(it.name, it.url, it.summary.orElse(null)) },
        linkedSpaces = getLinkedSpaces(arena).map { DetailLinkedSpace(it.apiEndpoint.orElse(null), it.website.orElse(null)) },
    )

    private fun OptionalDouble.toNumber(): Double? = if (isPresent && asDouble.isFinite()) asDouble else null

    private fun BridgeRoom.toKotlin() = MainframeRoom(
        id = id,
        name = name,
        state = when (getState(arena).discriminator!!) {
            BridgeRoomState.Discriminator.CLOSED -> MainframeRoomState.CLOSED
            BridgeRoomState.Discriminator.KEYHOLDER -> MainframeRoomState.KEYHOLDER
            BridgeRoomState.Discriminator.MEMBER -> MainframeRoomState.MEMBER
            BridgeRoomState.Discriminator.OPEN -> MainframeRoomState.OPEN
            BridgeRoomState.Discriminator.OPENPLUS -> MainframeRoomState.OPEN_PLUS
            BridgeRoomState.Discriminator.CLOSING -> MainframeRoomState.CLOSING
            BridgeRoomState.Discriminator.UNKNOWN -> MainframeRoomState.UNKNOWN
        },
        rawState = rawState,
        since = since.toInstant(),
    )

    private fun BridgeDirectoryItem.toKotlin() = DirectoryEntry(
        endpoint = endpoint,
        name = name,
        address = address.orElse(null),
        status = getStatus(arena).toKotlin(),
    )

    private fun BridgeStatus.toKotlin() = when (discriminator!!) {
        BridgeStatus.Discriminator.OPEN -> SpaceStatus.OPEN
        BridgeStatus.Discriminator.CLOSED -> SpaceStatus.CLOSED
        BridgeStatus.Discriminator.UNKNOWN -> SpaceStatus.UNKNOWN
    }

    private fun BridgeReadTiming.toKotlin() = ObservationTiming(
        source = when (source) {
            "direct" -> ObservationSource.DIRECT
            "aggregator" -> ObservationSource.AGGREGATOR
            "spacePush" -> ObservationSource.SPACE_PUSH
            else -> ObservationSource.UNKNOWN
        },
        observedAt = observedAt.toInstant(),
        receivedAt = receivedAt.toInstant(),
        expiresAt = expiresAt.toInstant(),
    )

    private fun OptionalDouble.toInstant(): Instant? {
        if (!isPresent) return null
        val seconds = asDouble
        if (!seconds.isFinite() || seconds < 0 || seconds > 253_402_300_799.0) return null
        val whole = floor(seconds).toLong()
        // Floor the fractional part: an exported expiry must never round later.
        val nanos = floor((seconds - whole) * 1_000_000_000).toLong().coerceIn(0, 999_999_999)
        return Instant.ofEpochSecond(whole, nanos)
    }
}
