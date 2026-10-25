package com.geocircle.shared

import kotlin.random.Random

object JoinCodes {
    const val LENGTH = 6

    private const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    fun generate(): String = generate(Random.Default)

    fun generate(random: Random): String =
        (1..LENGTH).map { ALPHABET[random.nextInt(ALPHABET.length)] }.joinToString("")

    fun normalize(input: String): String =
        input.filterNot { it.isWhitespace() || it == '-' }.uppercase()

    fun formatError(code: String): String? =
        if (code.length != LENGTH || code.any { it !in ALPHABET }) {
            "Join codes are $LENGTH letters and numbers."
        } else {
            null
        }
}
