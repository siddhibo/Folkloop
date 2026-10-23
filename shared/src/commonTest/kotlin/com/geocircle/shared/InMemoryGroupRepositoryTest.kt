package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class InMemoryGroupRepositoryTest {
    private val repository = InMemoryGroupRepository()
    private val point = GeoPoint(37.3349, -122.0090)

    @Test
    fun createsGroupWithTrimmedName() {
        val group = repository.createGroup("  Family  ")
        assertEquals("Family", group.name)
        assertEquals(listOf(group), repository.groups())
    }

    @Test
    fun rejectsInvalidGroupName() {
        assertFailsWith<IllegalArgumentException> { repository.createGroup("") }
        assertTrue(repository.groups().isEmpty())
    }

    @Test
    fun groupsGetUniqueIds() {
        val first = repository.createGroup("A")
        val second = repository.createGroup("B")
        assertNotEquals(first.id, second.id)
    }

    @Test
    fun groupHoldsMultipleGeofences() {
        val group = repository.createGroup("Family")
        val home = repository.addGeofence(group.id, "Home", point, 150.0)
        val school = repository.addGeofence(group.id, "School", GeoPoint(37.0, -122.0), 500.0)
        assertEquals(listOf(home, school), repository.geofences(group.id))
    }

    @Test
    fun geofencesAreKeptPerGroup() {
        val family = repository.createGroup("Family")
        val work = repository.createGroup("Work")
        repository.addGeofence(family.id, "Home", point, 150.0)
        assertTrue(repository.geofences(work.id).isEmpty())
    }

    @Test
    fun rejectsGeofenceForUnknownGroup() {
        assertFailsWith<IllegalArgumentException> {
            repository.addGeofence("missing", "Home", point, 150.0)
        }
    }

    @Test
    fun rejectsInvalidGeofence() {
        val group = repository.createGroup("Family")
        assertFailsWith<IllegalArgumentException> { repository.addGeofence(group.id, "Home", point, 50.0) }
        assertFailsWith<IllegalArgumentException> { repository.addGeofence(group.id, "Home", GeoPoint(100.0, 0.0), 150.0) }
        assertFailsWith<IllegalArgumentException> { repository.addGeofence(group.id, " ", point, 150.0) }
        assertTrue(repository.geofences(group.id).isEmpty())
    }

    @Test
    fun deletesGeofence() {
        val group = repository.createGroup("Family")
        val home = repository.addGeofence(group.id, "Home", point, 150.0)
        repository.deleteGeofence(home.id)
        assertTrue(repository.geofences(group.id).isEmpty())
    }
}
