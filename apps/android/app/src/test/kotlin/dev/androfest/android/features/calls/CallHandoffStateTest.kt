package dev.androfest.android.features.calls

import org.junit.Assert.*
import org.junit.Test

class CallHandoffStateTest {
    @Test
    fun repeatedCallUpdatesKeepOneIdentityAndApprovalIsExplicit() {
        val state = CallHandoffState()
        assertTrue(state.transition("ringing"))
        val token = state.snapshot.token!!
        repeat(50) {
            assertFalse(state.transition("ringing"))
            assertEquals(token, state.snapshot.token)
        }
        assertNull(state.snapshot.approval)
        state.approve(token)
        val approval = state.snapshot.approval
        assertTrue(state.transition("active"))
        assertEquals(token, state.snapshot.token)
        assertEquals(approval, state.snapshot.approval)
        repeat(50) { assertFalse(state.transition("active")) }
        state.transition("idle")
        assertNull(state.snapshot.token)
        assertNull(state.snapshot.approval)
        state.transition("ringing")
        assertNotEquals(token, state.snapshot.token)
        assertThrows(IllegalStateException::class.java) { state.approve(token) }
    }

    @Test
    fun answeringOnPhoneDoesNotApproveAudioAndReapprovalHasFreshIdentity() {
        val state = CallHandoffState()
        state.transition("active")
        assertNull(state.snapshot.approval)
        val token = state.snapshot.token!!
        state.approve(token)
        val first = state.snapshot.approval
        state.revoke(token)
        assertNull(state.snapshot.approval)
        state.approve(token)
        assertNotEquals(first, state.snapshot.approval)
    }
}
