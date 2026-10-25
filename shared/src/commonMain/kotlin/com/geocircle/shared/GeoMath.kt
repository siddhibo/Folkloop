package com.geocircle.shared

import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

object GeoMath {
    private const val EARTH_RADIUS_METERS = 6_371_000.0

    fun distanceMeters(from: GeoPoint, to: GeoPoint): Double {
        val lat1 = from.latitude.toRadians()
        val lat2 = to.latitude.toRadians()
        val deltaLat = (to.latitude - from.latitude).toRadians()
        val deltaLon = (to.longitude - from.longitude).toRadians()

        val a = sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * EARTH_RADIUS_METERS * asin(sqrt(a))
    }

    fun isInside(point: GeoPoint, geofence: Geofence): Boolean =
        distanceMeters(point, geofence.center) <= geofence.radiusMeters

    private fun Double.toRadians(): Double = this * PI / 180.0
}
