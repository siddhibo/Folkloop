package com.geocircle.shared

interface GroupRepository {
    fun groups(): List<TrackingGroup>

    @Throws(IllegalArgumentException::class)
    fun createGroup(name: String): TrackingGroup

    fun geofences(groupId: String): List<Geofence>

    @Throws(IllegalArgumentException::class)
    fun addGeofence(groupId: String, name: String, center: GeoPoint, radiusMeters: Double): Geofence

    fun deleteGeofence(geofenceId: String)

    fun members(groupId: String): List<GroupMember>

    @Throws(IllegalArgumentException::class)
    fun addSimulatedMember(groupId: String, displayName: String): GroupMember
}

class InMemoryGroupRepository : GroupRepository {
    private val groups = mutableListOf<TrackingGroup>()
    private val geofences = mutableListOf<Geofence>()
    private val members = mutableListOf<GroupMember>()
    private var nextId = 1

    override fun groups(): List<TrackingGroup> = groups.toList()

    @Throws(IllegalArgumentException::class)
    override fun createGroup(name: String): TrackingGroup {
        Validation.nameError(name)?.let { throw IllegalArgumentException(it) }
        val group = TrackingGroup(id = newId("group"), name = name.trim())
        groups += group
        members += GroupMember(newId("member"), group.id, OWNER_DISPLAY_NAME, MembershipStatus.OWNER)
        return group
    }

    override fun geofences(groupId: String): List<Geofence> =
        geofences.filter { it.groupId == groupId }

    @Throws(IllegalArgumentException::class)
    override fun addGeofence(groupId: String, name: String, center: GeoPoint, radiusMeters: Double): Geofence {
        require(groups.any { it.id == groupId }) { "Group not found." }
        val error = Validation.nameError(name)
            ?: Validation.coordinateError(center)
            ?: Validation.radiusError(radiusMeters)
        error?.let { throw IllegalArgumentException(it) }

        val geofence = Geofence(
            id = newId("geofence"),
            groupId = groupId,
            name = name.trim(),
            center = center,
            radiusMeters = radiusMeters,
        )
        geofences += geofence
        return geofence
    }

    override fun deleteGeofence(geofenceId: String) {
        geofences.removeAll { it.id == geofenceId }
    }

    override fun members(groupId: String): List<GroupMember> =
        members.filter { it.groupId == groupId }

    @Throws(IllegalArgumentException::class)
    override fun addSimulatedMember(groupId: String, displayName: String): GroupMember {
        require(groups.any { it.id == groupId }) { "Group not found." }
        Validation.nameError(displayName)?.let { throw IllegalArgumentException(it) }
        val trimmed = displayName.trim()
        require(members(groupId).none { it.displayName.equals(trimmed, ignoreCase = true) }) {
            "$trimmed is already in this group."
        }

        val member = GroupMember(newId("member"), groupId, trimmed, MembershipStatus.SIMULATED)
        members += member
        return member
    }

    private fun newId(prefix: String): String = "$prefix-${nextId++}"

    companion object {
        const val OWNER_DISPLAY_NAME = "You"
    }
}
