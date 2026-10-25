package com.geocircle.shared

data class ExitEvent(
    val id: String,
    val groupId: String,
    val memberId: String,
    val memberName: String,
    val geofenceId: String,
    val geofenceName: String,
    val isEntry: Boolean = false,
)

object MemberAlerts {
    fun recipients(members: List<GroupMember>, exitingMemberId: String): List<GroupMember> =
        members.filter { it.id != exitingMemberId }

    fun shouldAlert(currentUserId: String, event: ExitEvent): Boolean =
        event.memberId != currentUserId

    fun eventId(memberId: String, geofenceId: String, isEntry: Boolean, occurredAtMillis: Long): String =
        "${memberId}_${geofenceId}_${if (isEntry) "entry" else "exit"}_$occurredAtMillis"

    fun alert(event: ExitEvent, groupName: String): ExitAlert {
        val action = if (event.isEntry) "arrived at" else "left"
        return ExitAlert(
            title = "${event.memberName} $action ${event.geofenceName}",
            body = "${event.memberName} $action ${event.geofenceName} ($groupName).",
        )
    }
}
