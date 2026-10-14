package net.grafixmafia.spacestatekit

/** Optional provider details; an empty section never invalidates an opening state. */
data class SpaceDetails(
    val accessHint: String? = null,
    val countryCode: String? = null,
    val timezone: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val contacts: List<DetailContact> = emptyList(),
    val keyholders: List<DetailKeyholder> = emptyList(),
    val feeds: List<DetailFeed> = emptyList(),
    val projects: List<String> = emptyList(),
    val links: List<DetailLink> = emptyList(),
    val linkedSpaces: List<DetailLinkedSpace> = emptyList(),
)

data class DetailContact(val kind: String, val value: String)
data class DetailKeyholder(val name: String?, val ircNick: String?, val contacts: List<DetailContact>)
data class DetailFeed(val kind: String, val url: String, val format: String?)
data class DetailLink(val name: String, val url: String, val summary: String?)
data class DetailLinkedSpace(val apiEndpoint: String?, val website: String?)
