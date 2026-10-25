package com.geocircle.shared

enum class PresenceStatus {
    INSIDE,
    OUTSIDE,
    STALE,
    UNKNOWN,
}

data class RecordedCrossing(
    val memberId: String,
    val geofenceId: String,
    val isEntry: Boolean,
    val occurredAtMillis: Long,
)

data class MemberPresence(
    val memberId: String,
    val status: PresenceStatus,
    val lastRecordedAtMillis: Long?,
    val lastWasEntry: Boolean?,
)

object GroupPresence {
    const val STALE_AFTER_MILLIS = 12L * 60 * 60 * 1000

    fun forGeofence(
        geofenceId: String,
        memberIds: List<String>,
        crossings: List<RecordedCrossing>,
        nowMillis: Long,
    ): List<MemberPresence> {
        val latestByMember = crossings
            .filter { it.geofenceId == geofenceId }
            .groupBy { it.memberId }
            .mapValues { (_, memberCrossings) -> memberCrossings.maxBy { it.occurredAtMillis } }
        return memberIds.map { memberId ->
            val latest = latestByMember[memberId]
            val status = when {
                latest == null -> PresenceStatus.UNKNOWN
                nowMillis - latest.occurredAtMillis > STALE_AFTER_MILLIS -> PresenceStatus.STALE
                latest.isEntry -> PresenceStatus.INSIDE
                else -> PresenceStatus.OUTSIDE
            }
            MemberPresence(memberId, status, latest?.occurredAtMillis, latest?.isEntry)
        }
    }
}
