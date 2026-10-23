package com.geocircle.shared

/**
 * Input rules shared by every platform.
 * Each check returns an error message, or null when the input is valid.
 */
object Validation {
    const val MAX_NAME_LENGTH = 40

    // iOS region monitoring is unreliable below roughly 100 m.
    const val MIN_RADIUS_METERS = 100.0
    const val MAX_RADIUS_METERS = 2_000.0

    fun nameError(name: String): String? {
        val trimmed = name.trim()
        return when {
            trimmed.isEmpty() -> "Name cannot be empty."
            trimmed.length > MAX_NAME_LENGTH -> "Name must be $MAX_NAME_LENGTH characters or fewer."
            else -> null
        }
    }

    fun coordinateError(point: GeoPoint): String? = when {
        point.latitude.isNaN() || point.longitude.isNaN() -> "Coordinates must be numbers."
        point.latitude !in -90.0..90.0 -> "Latitude must be between -90 and 90."
        point.longitude !in -180.0..180.0 -> "Longitude must be between -180 and 180."
        else -> null
    }

    fun radiusError(radiusMeters: Double): String? =
        if (radiusMeters.isNaN() || radiusMeters !in MIN_RADIUS_METERS..MAX_RADIUS_METERS) {
            "Radius must be between ${MIN_RADIUS_METERS.toInt()} and ${MAX_RADIUS_METERS.toInt()} m."
        } else {
            null
        }
}
