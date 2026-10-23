package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertTrue

class GreetingTest {
    @Test
    fun greetingMentionsKotlin() {
        assertTrue(Greeting().greet().startsWith("Hello from Kotlin"))
    }
}
