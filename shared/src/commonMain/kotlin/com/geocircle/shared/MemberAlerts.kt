package com.geocircle.shared

/** A geofence exit reported by one member of a group. */
data class ExitEvent(
    val id: String,
    val groupId: String,
    val memberId: String,
    val memberName: String,
    val geofenceId: String,
    val geofenceName: String,
)

/** Decides who hears about an exit. The person who left never gets the member alert. */
object MemberAlerts {
    fun recipients(members: List<GroupMember>, exitingMemberId: String): List<GroupMember> =
        members.filter { it.id != exitingMemberId }

    fun shouldAlert(currentUserId: String, event: ExitEvent): Boolean =
        event.memberId != currentUserId

    fun alert(event: ExitEvent, groupName: String): ExitAlert = ExitAlert(
        title = "${event.memberName} left ${event.geofenceName}",
        body = "${event.memberName} left ${event.geofenceName} ($groupName).",
    )
}
