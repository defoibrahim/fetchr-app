package com.defo.fetchr

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class YtDlpScheduleTest {
    private val hour = 60L * 60 * 1000
    private val now = 1_800_000_000_000L

    @Test
    fun notDueWhenDisabled() {
        assertFalse(YtDlpSchedule.isDue(0L, now, enabled = false))
        assertFalse(YtDlpSchedule.isDue(now + hour, now, enabled = false))
    }

    @Test
    fun dueWhenNeverChecked() {
        assertTrue(YtDlpSchedule.isDue(0L, now, enabled = true))
    }

    @Test
    fun notDueBeforeTwentyFourHours() {
        assertFalse(YtDlpSchedule.isDue(now - 23 * hour, now, enabled = true))
    }

    @Test
    fun dueAtTwentyFourHours() {
        assertTrue(YtDlpSchedule.isDue(now - 24 * hour, now, enabled = true))
    }

    @Test
    fun dueWhenTheClockMovedBack() {
        assertTrue(YtDlpSchedule.isDue(now + hour, now, enabled = true))
    }
}
