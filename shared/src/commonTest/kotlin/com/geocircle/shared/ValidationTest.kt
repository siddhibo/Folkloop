package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class ValidationTest {
    @Test
    fun acceptsNormalName() {
        assertNull(Validation.nameError("Family"))
    }

    @Test
    fun rejectsBlankName() {
        assertNotNull(Validation.nameError("   "))
    }

    @Test
    fun acceptsNameAtMaxLengthAfterTrimming() {
        assertNull(Validation.nameError("  " + "a".repeat(Validation.MAX_NAME_LENGTH) + "  "))
    }

    @Test
    fun rejectsTooLongName() {
        assertNotNull(Validation.nameError("a".repeat(Validation.MAX_NAME_LENGTH + 1)))
    }

    @Test
    fun acceptsCoordinateEdges() {
        assertNull(Validation.coordinateError(GeoPoint(90.0, -180.0)))
        assertNull(Validation.coordinateError(GeoPoint(-90.0, 180.0)))
    }

    @Test
    fun rejectsOutOfRangeCoordinates() {
        assertNotNull(Validation.coordinateError(GeoPoint(90.1, 0.0)))
        assertNotNull(Validation.coordinateError(GeoPoint(0.0, -180.1)))
        assertNotNull(Validation.coordinateError(GeoPoint(Double.NaN, 0.0)))
    }

    @Test
    fun acceptsRadiusLimits() {
        assertNull(Validation.radiusError(Validation.MIN_RADIUS_METERS))
        assertNull(Validation.radiusError(Validation.MAX_RADIUS_METERS))
    }

    @Test
    fun rejectsRadiusOutsideLimits() {
        assertNotNull(Validation.radiusError(99.9))
        assertNotNull(Validation.radiusError(2_000.1))
        assertNotNull(Validation.radiusError(Double.NaN))
    }
}
