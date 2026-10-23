package com.geocircle.shared

/**
 * Stores groups and their geofences.
 * Invalid input throws IllegalArgumentException; Swift sees these functions as `throws`.
 */
interface GroupRepository {
    fun groups(): List<TrackingGroup>

    @Throws(IllegalArgumentException::class)
    fun createGroup(name: String): TrackingGroup

    fun geofences(groupId: String): List<Geofence>

    @Throws(IllegalArgumentException::class)
    fun addGeofence(groupId: String, name: String, center: GeoPoint, radiusMeters: Double): Geofence

    fun deleteGeofence(geofenceId: String)
}

/** Keeps everything in memory. Data is lost when the app restarts; Firestore replaces this later. */
class InMemoryGroupRepository : GroupRepository {
    private val groups = mutableListOf<TrackingGroup>()
    private val geofences = mutableListOf<Geofence>()
    private var nextId = 1

    override fun groups(): List<TrackingGroup> = groups.toList()

    @Throws(IllegalArgumentException::class)
    override fun createGroup(name: String): TrackingGroup {
        Validation.nameError(name)?.let { throw IllegalArgumentException(it) }
        val group = TrackingGroup(id = newId("group"), name = name.trim())
        groups += group
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

    private fun newId(prefix: String): String = "$prefix-${nextId++}"
}
