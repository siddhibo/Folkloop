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
        val near = geofence("near", here.latitude + 0.01)
        val far = geofence("far", here.latitude + 0.1)
        val bigFar = geofence("bigFar", here.latitude + 0.02, radiusMeters = 2_000.0)
        val selected = GeofenceMonitoring.selectForMonitoring(listOf(far, near, bigFar), here, limit = 2)
        assertEquals(listOf("bigFar", "near"), selected.map { it.id })
    }

    @Test
    fun zeroLimitSelectsNothingAndNegativeIsRejected() {
        assertTrue(GeofenceMonitoring.selectForMonitoring(listOf(geofence("a", 37.0)), here, limit = 0).isEmpty())
        assertFailsWith<IllegalArgumentException> { GeofenceMonitoring.selectForMonitoring(emptyList(), here, limit = -1) }
    }

    @Test
    fun onlyOutsideToInsideIsAnEntry() {
        assertTrue(GeofenceMonitoring.isEntry(RegionState.OUTSIDE, RegionState.INSIDE))
        assertFalse(GeofenceMonitoring.isEntry(RegionState.UNKNOWN, RegionState.INSIDE))
        assertFalse(GeofenceMonitoring.isEntry(RegionState.INSIDE, RegionState.INSIDE))
        assertFalse(GeofenceMonitoring.isEntry(RegionState.OUTSIDE, RegionState.UNKNOWN))
        assertFalse(GeofenceMonitoring.isEntry(RegionState.INSIDE, RegionState.OUTSIDE))
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
    fun sameRegionToleratesRoundingButNotRealEdits() {
        assertTrue(GeofenceMonitoring.isSameRegion(here, 300.0, GeoPoint(here.latitude + 0.000001, here.longitude), 300.0))
        assertFalse(GeofenceMonitoring.isSameRegion(here, 300.0, GeoPoint(here.latitude + 0.001, here.longitude), 300.0))
        assertFalse(GeofenceMonitoring.isSameRegion(here, 300.0, here, 350.0))
    }

    @Test
    fun exitAlertNamesPlaceAndGroup() {
        val alert = GeofenceMonitoring.exitAlert(geofence("a", 37.0), groupName = "Family", otherMemberCount = 0)
        assertEquals("Left Place a", alert.title)
        assertEquals("You left Place a (Family). No other members are in this group yet.", alert.body)
    }

    @Test
    fun exitAlertSaysOtherMembersOnlySeeItWhileAppIsOpen() {
        val one = GeofenceMonitoring.exitAlert(geofence("a", 37.0), "Family", otherMemberCount = 1)
        val two = GeofenceMonitoring.exitAlert(geofence("a", 37.0), "Family", otherMemberCount = 2)
        assertTrue("1 other member, who sees it only if Folkloop is open" in one.body)
        assertTrue("2 other members, who see it only if Folkloop is open" in two.body)
    }
}
