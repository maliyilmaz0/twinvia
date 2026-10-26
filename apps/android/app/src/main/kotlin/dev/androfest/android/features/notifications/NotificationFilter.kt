package dev.androfest.android.features.notifications

/** Platform-independent delivery rules; Android metadata is read by the listener. */
object NotificationFilter {
    fun shouldHide(
        excluded: Boolean,
        hidePersistent: Boolean,
        groupSummary: Boolean,
        hasContent: Boolean,
        ongoing: Boolean,
        clearable: Boolean,
        foregroundService: Boolean,
        category: String?,
    ): Boolean {
        if (excluded || groupSummary || !hasContent) return true
        // Ringing calls and alarms can be ongoing/non-clearable too.
        if (category == "call" || category == "alarm") return false
        return hidePersistent &&
            (ongoing ||
                !clearable ||
                foregroundService ||
                category in setOf("service", "status", "progress"))
    }
}
