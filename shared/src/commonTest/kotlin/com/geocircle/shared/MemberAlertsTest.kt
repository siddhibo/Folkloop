package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MemberAlertsTest {
    private val alice = GroupMember("alice", "g1", "Alice", MembershipStatus.OWNER)
    private val bob = GroupMember("bob", "g1", "Bob", MembershipStatus.MEMBER)
    private val carol = GroupMember("carol", "g1", "Carol", MembershipStatus.MEMBER)
    private val bobLeftOffice = ExitEvent("e1", "g1", memberId = "bob", memberName = "Bob", geofenceId = "f1", geofenceName = "Office")

    @Test
    fun recipientsExcludeThePersonWhoLeft() {
        assertEquals(listOf(alice, carol), MemberAlerts.recipients(listOf(alice, bob, carol), exitingMemberId = "bob"))
    }

    @Test
    fun aGroupOfOneHasNoRecipients() {
        assertTrue(MemberAlerts.recipients(listOf(alice), exitingMemberId = "alice").isEmpty())
    }

    @Test
    fun onlyOtherMembersAreAlerted() {
        assertTrue(MemberAlerts.shouldAlert(currentUserId = "alice", event = bobLeftOffice))
        assertFalse(MemberAlerts.shouldAlert(currentUserId = "bob", event = bobLeftOffice))
    }

    @Test
    fun eventIdIsStableForOneOccurrenceAndDistinctOtherwise() {
        val first = MemberAlerts.eventId("bob", "office", isEntry = false, occurredAtMillis = 1_700_000_000_000)
        assertEquals("bob_office_exit_1700000000000", first)
        assertEquals(first, MemberAlerts.eventId("bob", "office", isEntry = false, occurredAtMillis = 1_700_000_000_000))
        assertTrue(first != MemberAlerts.eventId("bob", "office", isEntry = false, occurredAtMillis = 1_700_000_060_000))
        assertTrue(first != MemberAlerts.eventId("carol", "office", isEntry = false, occurredAtMillis = 1_700_000_000_000))
        assertTrue(first != MemberAlerts.eventId("bob", "office", isEntry = true, occurredAtMillis = 1_700_000_000_000))
    }

    @Test
    fun entryAlertSaysArrived() {
        val alert = MemberAlerts.alert(bobLeftOffice.copy(isEntry = true), groupName = "Family")
        assertEquals("Bob arrived at Office", alert.title)
        assertEquals("Bob arrived at Office (Family).", alert.body)
    }

    @Test
    fun alertNamesMemberPlaceAndGroup() {
        val alert = MemberAlerts.alert(bobLeftOffice, groupName = "Family")
        assertEquals("Bob left Office", alert.title)
        assertEquals("Bob left Office (Family).", alert.body)
    }
}
