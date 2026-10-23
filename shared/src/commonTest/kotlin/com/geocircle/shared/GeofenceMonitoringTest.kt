package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GeofenceMonitoringTest {
    private val here = GeoPoint(37.3349, -122.0090)

    private fun geofence(id: String, latitude: Double, radiusMeters: Double = 100.0) =
        Geofence(id, "group-1", "Place $id", GeoPoint(latitude, here.longitude), radiusMeters)

    @Test
    fun keepsAllWhenUnderLimit() {
        val all = listOf(geofence("a", 37.0), geofence("b", 38.0))
        assertEquals(all, GeofenceMonitoring.selectForMonitoring(all, here, limit = 20))
    }

    @Test
    fun withoutLocationKeepsOldestUpToLimit() {
        val all = (1..25).map { geofence("$it", 37.0 + it * 0.01) }
        val selected = GeofenceMonitoring.selectForMonitoring(all, currentLocation = null, limit = GeofenceMonitoring.IOS_REGION_LIMIT)
        assertEquals(all.take(20), selected)
    }

    @Test
    fun withLocationKeepsClosestEdges() {
        val near = geofence("near", here.latitude + 0.01) // ~1.1 km away, edge ~1 km
        val far = geofence("far", here.latitude + 0.1) // ~11 km away
        val bigFar = geofence("bigFar", here.latitude + 0.02, radiusMeters = 2_000.0) // edge already reached
        val selected = GeofenceMonitoring.selectForMonitoring(listOf(far, near, bigFar), here, limit = 2)
        assertEquals(listOf("bigFar", "near"), selected.map { it.id })
    }

    @Test
    fun zeroLimitSelectsNothingAndNegativeIsRejected() {
        assertTrue(GeofenceMonitoring.selectForMonitoring(listOf(geofence("a", 37.0)), here, limit = 0).isEmpty())
        assertFailsWith<IllegalArgumentException> { GeofenceMonitoring.selectForMonitoring(emptyList(), here, limit = -1) }
    }

    @Test
    fun onlyInsideToOutsideIsAnExit() {
        assertTrue(GeofenceMonitoring.isExit(RegionState.INSIDE, RegionState.OUTSIDE))
        assertFalse(GeofenceMonitoring.isExit(RegionState.UNKNOWN, RegionState.OUTSIDE))
        assertFalse(GeofenceMonitoring.isExit(RegionState.OUTSIDE, RegionState.OUTSIDE))
        assertFalse(GeofenceMonitoring.isExit(RegionState.OUTSIDE, RegionState.INSIDE))
        assertFalse(GeofenceMonitoring.isExit(RegionState.INSIDE, RegionState.INSIDE))
        assertFalse(GeofenceMonitoring.isExit(RegionState.INSIDE, RegionState.UNKNOWN))
    }

    @Test
    fun exitAlertNamesPlaceAndGroupAndSaysItIsLocal() {
        val alert = GeofenceMonitoring.exitAlert(geofence("a", 37.0), groupName = "Family")
        assertEquals("Left Place a", alert.title)
        assertTrue("Place a" in alert.body)
        assertTrue("Family" in alert.body)
        assertTrue("Only this device" in alert.body)
    }
}
