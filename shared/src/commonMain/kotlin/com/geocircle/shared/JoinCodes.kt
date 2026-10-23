package com.geocircle.shared

import kotlin.random.Random

/** Short codes that let someone join a group. Knowing the code is the only permission needed. */
object JoinCodes {
    const val LENGTH = 6

    // No 0/O or 1/I/L, so codes are easy to read aloud and type.
    private const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    fun generate(): String = generate(Random.Default)

    fun generate(random: Random): String =
        (1..LENGTH).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")

    /** Accepts what people actually type: lowercase, spaces or dashes. */
    fun normalize(input: String): String =
        input.filterNot { it.isWhitespace() || it == '-' }.uppercase()

    fun formatError(code: String): String? =
        if (code.length != LENGTH || code.any { it !in ALPHABET }) {
            "Join codes are $LENGTH letters and numbers."
        } else {
            null
        }
}
