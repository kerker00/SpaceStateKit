package net.grafixmafia.spacestatekit

import java.time.Instant
import java.util.Optional
import java.util.OptionalDouble
import kotlinx.coroutines.future.await
import net.grafixmafia.spacestatekit.bridge.SpaceStateService
import org.swift.swiftkit.core.SwiftArena
import net.grafixmafia.spacestatekit.bridge.DirectoryItem as BridgeDirectoryItem
import net.grafixmafia.spacestatekit.bridge.Room as BridgeRoom
import net.grafixmafia.spacestatekit.bridge.RoomState as BridgeRoomState
import net.grafixmafia.spacestatekit.bridge.Space as BridgeSpace
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

/**
 * SpaceStateKit's `StatusService` for Kotlin: reads through SpacePush and falls back to
 * the spaces directly. Every call runs in Swift; failures surface as exceptions.
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

    suspend fun space(endpoint: String): SpaceInfo = service.space(endpoint, arena).await().toKotlin()

    suspend fun mainframeRooms(): List<MainframeRoom> = service.mainframeRooms(arena).await().map { it.toKotlin() }

    suspend fun directory(): List<DirectoryEntry> = service.directory(arena).await().map { it.toKotlin() }

    companion object {
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
    )

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

    private fun OptionalDouble.toInstant(): Instant? =
        if (isPresent) Instant.ofEpochMilli((asDouble * 1000).toLong()) else null
}
