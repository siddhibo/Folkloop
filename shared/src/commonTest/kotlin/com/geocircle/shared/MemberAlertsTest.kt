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
    fun alertNamesMemberPlaceAndGroup() {
        val alert = MemberAlerts.alert(bobLeftOffice, groupName = "Family")
        assertEquals("Bob left Office", alert.title)
        assertEquals("Bob left Office (Family).", alert.body)
    }
}
