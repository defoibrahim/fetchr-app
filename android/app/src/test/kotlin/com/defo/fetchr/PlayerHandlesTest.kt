package com.defo.fetchr

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class PlayerHandlesTest {
    private val detached = mutableListOf<LongArray>()
    private val cleared = mutableListOf<Long>()
    private val players = PlayerHandles(detach = { detached += it }, clearWakeup = { cleared += it })

    @Test
    fun detachesEveryOpenPlayerOnce() {
        players.track(11)
        players.track(22)
        players.untrack(11)
        players.detachAll()
        players.detachAll()
        assertEquals(1, detached.size)
        assertArrayEquals(longArrayOf(22), detached.single())
    }

    @Test
    fun untrackClearsTheWakeupCallback() {
        players.track(11)
        players.untrack(11)
        players.untrack(0)
        assertEquals(listOf(11L), cleared)
    }

    @Test
    fun skipsNativeWithNothingOpen() {
        players.track(0)
        players.detachAll()
        assertEquals(0, detached.size)
    }

    @Test
    fun aPlayerTrackedTwiceIsDetachedOnce() {
        players.track(7)
        players.track(7)
        players.detachAll()
        assertArrayEquals(longArrayOf(7), detached.single())
    }
}
