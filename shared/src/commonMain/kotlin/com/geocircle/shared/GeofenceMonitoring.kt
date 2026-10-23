package com.geocircle.shared

/** What the device last reported for one geofence. */
enum class RegionState {
    UNKNOWN,
    INSIDE,
    OUTSIDE,
}

/** Text for an exit alert shown on this device. */
data class ExitAlert(
    val title: String,
    val body: String,
)

/** Platform-independent rules for watching geofences. Each platform does the actual location monitoring. */
object GeofenceMonitoring {
    /** iOS lets one app monitor at most 20 regions at a time. */
    const val IOS_REGION_LIMIT = 20

    /**
     * Picks which geofences to monitor when there are more than [limit].
     * With a known location, the geofences whose edge is closest are kept; otherwise the oldest ones are.
     */
    fun selectForMonitoring(geofences: List<Geofence>, currentLocation: GeoPoint?, limit: Int): List<Geofence> {
        require(limit >= 0) { "Limit cannot be negative." }
        if (currentLocation == null) return geofences.take(limit)
        return geofences
            .sortedBy { GeoMath.distanceMeters(currentLocation, it.center) - it.radiusMeters }
            .take(limit)
    }

    /** Only inside -> outside counts, so starting to monitor while already outside does not alert. */
    fun isExit(previous: RegionState, current: RegionState): Boolean =
        previous == RegionState.INSIDE && current == RegionState.OUTSIDE

    /**
     * The alert the person who left sees on their own device.
     * Other members only get a live in-app alert while GeoCircle is running on their device; it is not a push notification.
     */
    fun exitAlert(geofence: Geofence, groupName: String, otherMemberCount: Int): ExitAlert = ExitAlert(
        title = "Left ${geofence.name}",
        body = "You left ${geofence.name} ($groupName). " + when (otherMemberCount) {
            0 -> "No other members are in this group yet."
            1 -> "Shared with 1 other member, who sees it only if GeoCircle is open."
            else -> "Shared with $otherMemberCount other members, who see it only if GeoCircle is open."
        },
    )
}
