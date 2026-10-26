package dev.androfest.android.features.notifications

import org.junit.Assert.*
import org.junit.Test

class NotificationFilterTest {
    private fun hidden(
        excluded: Boolean = false,
        enabled: Boolean = true,
        summary: Boolean = false,
        content: Boolean = true,
        ongoing: Boolean = false,
        clearable: Boolean = true,
        service: Boolean = false,
        category: String? = null,
    ) =
        NotificationFilter.shouldHide(
            excluded,
            enabled,
            summary,
            content,
            ongoing,
            clearable,
            service,
            category,
        )

    @Test
    fun `ordinary messages and calls remain deliverable`() {
        listOf(null, "msg", "call", "email", "alarm", "reminder").forEach {
            assertFalse(hidden(category = it))
        }
        listOf("call", "alarm").forEach {
            assertFalse(hidden(ongoing = true, clearable = false, service = true, category = it))
        }
    }

    @Test
    fun `persistent services and phone status are suppressed`() {
        assertTrue(hidden(ongoing = true))
        assertTrue(hidden(clearable = false))
        assertTrue(hidden(service = true))
        listOf("service", "status", "progress").forEach { assertTrue(hidden(category = it)) }
    }

    @Test
    fun `user can allow persistent notifications without allowing summaries`() {
        assertFalse(
            hidden(
                enabled = false,
                ongoing = true,
                clearable = false,
                service = true,
                category = "progress",
            )
        )
        assertTrue(hidden(enabled = false, summary = true))
    }

    @Test
    fun `excluded application stays blocked regardless of persistent preference`() {
        assertTrue(hidden(excluded = true, enabled = false, category = "msg"))
    }

    @Test
    fun `empty notifications and duplicate group headers are suppressed`() {
        assertTrue(hidden(content = false))
        assertTrue(hidden(summary = true))
    }
}
