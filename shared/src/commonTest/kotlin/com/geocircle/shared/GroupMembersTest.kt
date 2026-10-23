package com.geocircle.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class GroupMembersTest {
    private val repository = InMemoryGroupRepository()

    @Test
    fun newGroupStartsWithOwner() {
        val group = repository.createGroup("Family")
        val owner = repository.members(group.id).single()
        assertEquals(InMemoryGroupRepository.OWNER_DISPLAY_NAME, owner.displayName)
        assertEquals(MembershipStatus.OWNER, owner.status)
    }

    @Test
    fun addsSimulatedMemberWithTrimmedName() {
        val group = repository.createGroup("Family")
        val alex = repository.addSimulatedMember(group.id, "  Alex  ")
        assertEquals("Alex", alex.displayName)
        assertEquals(MembershipStatus.SIMULATED, alex.status)
        assertEquals(group.id, alex.groupId)
        assertEquals(listOf("You", "Alex"), repository.members(group.id).map { it.displayName })
    }

    @Test
    fun membersGetUniqueIds() {
        val group = repository.createGroup("Family")
        val alex = repository.addSimulatedMember(group.id, "Alex")
        val sam = repository.addSimulatedMember(group.id, "Sam")
        val ids = repository.members(group.id).map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        assertNotEquals(alex.id, sam.id)
    }

    @Test
    fun membersAreKeptPerGroup() {
        val family = repository.createGroup("Family")
        val work = repository.createGroup("Work")
        repository.addSimulatedMember(family.id, "Alex")
        assertEquals(listOf("You"), repository.members(work.id).map { it.displayName })
    }

    @Test
    fun rejectsInvalidMemberName() {
        val group = repository.createGroup("Family")
        assertFailsWith<IllegalArgumentException> { repository.addSimulatedMember(group.id, "   ") }
        assertFailsWith<IllegalArgumentException> {
            repository.addSimulatedMember(group.id, "a".repeat(Validation.MAX_NAME_LENGTH + 1))
        }
        assertEquals(1, repository.members(group.id).size)
    }

    @Test
    fun rejectsDuplicateNameIgnoringCase() {
        val group = repository.createGroup("Family")
        repository.addSimulatedMember(group.id, "Alex")
        assertFailsWith<IllegalArgumentException> { repository.addSimulatedMember(group.id, " alex ") }
        assertFailsWith<IllegalArgumentException> { repository.addSimulatedMember(group.id, "you") }
        assertEquals(2, repository.members(group.id).size)
    }

    @Test
    fun sameNameAllowedInDifferentGroups() {
        val family = repository.createGroup("Family")
        val work = repository.createGroup("Work")
        repository.addSimulatedMember(family.id, "Alex")
        repository.addSimulatedMember(work.id, "Alex")
        assertTrue(repository.members(work.id).any { it.displayName == "Alex" })
    }

    @Test
    fun rejectsMemberForUnknownGroup() {
        assertFailsWith<IllegalArgumentException> { repository.addSimulatedMember("missing", "Alex") }
    }
}
