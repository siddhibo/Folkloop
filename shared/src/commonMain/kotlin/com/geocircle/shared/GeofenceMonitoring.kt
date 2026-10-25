package com.geocircle.shared

import kotlin.math.abs

enum class RegionState {
    UNKNOWN,
    INSIDE,
    OUTSIDE,
}

data class ExitAlert(
    val title: String,
    val body: String,
)

object GeofenceMonitoring {
    const val IOS_REGION_LIMIT = 20

    fun selectForMonitoring(geofences: List<Geofence>, currentLocation: GeoPoint?, limit: Int): List<Geofence> {
        require(limit >= 0) { "Limit cannot be negative." }
        if (currentLocation == null) return geofences.take(limit)
        return geofences
            .sortedBy { GeoMath.distanceMeters(currentLocation, it.center) - it.radiusMeters }
            .take(limit)
    }

    fun isExit(previous: RegionState, current: RegionState): Boolean =
        previous == RegionState.INSIDE && current == RegionState.OUTSIDE

    fun isEntry(previous: RegionState, current: RegionState): Boolean =
        previous == RegionState.OUTSIDE && current == RegionState.INSIDE

    const val REGION_MATCH_TOLERANCE_METERS = 1.0

    fun isSameRegion(center: GeoPoint, radiusMeters: Double, otherCenter: GeoPoint, otherRadiusMeters: Double): Boolean =
        GeoMath.distanceMeters(center, otherCenter) < REGION_MATCH_TOLERANCE_METERS &&
            abs(radiusMeters - otherRadiusMeters) < REGION_MATCH_TOLERANCE_METERS

    fun exitAlert(geofence: Geofence, groupName: String, otherMemberCount: Int): ExitAlert = ExitAlert(
        title = "Left ${geofence.name}",
        body = "You left ${geofence.name} ($groupName). " + when (otherMemberCount) {
            0 -> "No other members are in this group yet."
            1 -> "Shared with 1 other member, who sees it only if Folkloop is open."
            else -> "Shared with $otherMemberCount other members, who see it only if Folkloop is open."
        },
    )
}
