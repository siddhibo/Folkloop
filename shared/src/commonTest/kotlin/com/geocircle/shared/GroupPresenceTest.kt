package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertEquals

class GroupPresenceTest {
    private val now = 1_700_000_000_000L
    private val minute = 60_000L

    private fun crossing(member: String, isEntry: Boolean, minutesAgo: Long, geofence: String = "office") =
        RecordedCrossing(member, geofence, isEntry, now - minutesAgo * minute)

    private fun statuses(crossings: List<RecordedCrossing>, members: List<String> = listOf("alice", "bob", "carol")) =
        GroupPresence.forGeofence("office", members, crossings, now).associate { it.memberId to it.status }

    @Test
    fun latestRecordedCrossingDecidesInsideOrOutside() {
        val result = statuses(
            listOf(
                crossing("alice", isEntry = false, minutesAgo = 30),
                crossing("alice", isEntry = true, minutesAgo = 5),
                crossing("bob", isEntry = true, minutesAgo = 20),
                crossing("bob", isEntry = false, minutesAgo = 10),
            ),
        )
        assertEquals(PresenceStatus.INSIDE, result["alice"])
        assertEquals(PresenceStatus.OUTSIDE, result["bob"])
    }

    @Test
    fun membersWithoutRecordsAreUnknownNotOutside() {
        assertEquals(PresenceStatus.UNKNOWN, statuses(emptyList())["carol"])
    }

    @Test
    fun oldRecordsAreStaleNotOutside() {
        val result = statuses(listOf(crossing("bob", isEntry = false, minutesAgo = 13 * 60)))
        assertEquals(PresenceStatus.STALE, result["bob"])
    }

    @Test
    fun crossingsAtOtherGeofencesAreIgnored() {
        val result = statuses(listOf(crossing("alice", isEntry = true, minutesAgo = 1, geofence = "gym")))
        assertEquals(PresenceStatus.UNKNOWN, result["alice"])
    }

    @Test
    fun crossingsFromFormerMembersAreNotCounted() {
        val presence = GroupPresence.forGeofence("office", listOf("alice"), listOf(crossing("mallory", true, 1)), now)
        assertEquals(listOf("alice"), presence.map { it.memberId })
    }
}
