package com.geocircle.shared

/** A latitude/longitude pair in degrees. */
data class GeoPoint(
    val latitude: Double,
    val longitude: Double,
)

/** A group of people who share geofences. Members are added in a later milestone. */
data class TrackingGroup(
    val id: String,
    val name: String,
)

/** A circular area that belongs to one tracking group. */
data class Geofence(
    val id: String,
    val groupId: String,
    val name: String,
    val center: GeoPoint,
    val radiusMeters: Double,
)

/** How someone belongs to a group. Real invitations arrive with the backend milestone. */
enum class MembershipStatus {
    /** Created the group on this device. */
    OWNER,

    /** Added locally for testing. No real person has been invited. */
    SIMULATED,
}

data class GroupMember(
    val id: String,
    val groupId: String,
    val displayName: String,
    val status: MembershipStatus,
)
