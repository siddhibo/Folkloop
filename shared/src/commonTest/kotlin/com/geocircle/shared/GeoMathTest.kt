package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GeoMathTest {
    private val center = GeoPoint(37.3349, -122.0090)

    @Test
    fun distanceToSamePointIsZero() {
        assertEquals(0.0, GeoMath.distanceMeters(center, center), 0.001)
    }

    @Test
    fun oneDegreeOfLatitudeIsAbout111Km() {
        val north = GeoPoint(1.0, 0.0)
        assertEquals(111_195.0, GeoMath.distanceMeters(GeoPoint(0.0, 0.0), north), 10.0)
    }

    @Test
    fun knownCityDistance() {
        val london = GeoPoint(51.5074, -0.1278)
        val paris = GeoPoint(48.8566, 2.3522)
        assertEquals(343_500.0, GeoMath.distanceMeters(london, paris), 1_000.0)
    }

    @Test
    fun insideAndOutsideGeofence() {
        val geofence = Geofence("g1", "group-1", "Home", center, radiusMeters = 200.0)
        assertTrue(GeoMath.isInside(GeoPoint(center.latitude + 0.001, center.longitude), geofence))
        assertFalse(GeoMath.isInside(GeoPoint(center.latitude + 0.003, center.longitude), geofence))
    }
}
