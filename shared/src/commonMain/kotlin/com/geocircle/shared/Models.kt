package com.geocircle.shared

data class GeoPoint(
    val latitude: Double,
    val longitude: Double,
)

data class TrackingGroup(
    val id: String,
    val name: String,
)

data class Geofence(
    val id: String,
    val groupId: String,
    val name: String,
    val center: GeoPoint,
    val radiusMeters: Double,
)

enum class MembershipStatus {
    OWNER,

    MEMBER,

    SIMULATED,
}

data class GroupMember(
    val id: String,
    val groupId: String,
    val displayName: String,
    val status: MembershipStatus,
)
