package com.geocircle.shared

import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class JoinCodesTest {
    @Test
    fun generatedCodesAreValid() {
        val random = Random(42)
        repeat(200) {
            val code = JoinCodes.generate(random)
            assertEquals(JoinCodes.LENGTH, code.length)
            assertNull(JoinCodes.formatError(code), "Invalid code: $code")
        }
    }

    @Test
    fun codesVary() {
        val random = Random(7)
        assertNotEquals(JoinCodes.generate(random), JoinCodes.generate(random))
    }

    @Test
    fun normalizesTypedInput() {
        assertEquals("ABC234", JoinCodes.normalize(" abc-234 "))
    }

    @Test
    fun rejectsWrongLengthAndConfusingCharacters() {
        assertNotNull(JoinCodes.formatError("ABC23"))
        assertNotNull(JoinCodes.formatError("ABC2345"))
        assertNotNull(JoinCodes.formatError("ABC0O1"))
        assertNotNull(JoinCodes.formatError("abc234"))
    }
}
