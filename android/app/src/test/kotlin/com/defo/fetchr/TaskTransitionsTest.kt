package com.defo.fetchr

import com.defo.fetchr.TaskFixtures.task
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class TaskTransitionsTest {
    private fun others(vararg keep: TaskStatus) = TaskStatus.values().filterNot { it in keep }

    @Test fun pauseFromQueuedAndRunningKeepsProgressAndBytes() {
        for (from in listOf(TaskStatus.QUEUED, TaskStatus.RUNNING)) {
            val paused = TaskTransitions.pause(task(status = from, stalled = true))!!
            assertEquals(TaskStatus.PAUSED, paused.status)
            assertEquals(0.4, paused.progress, 0.0)
            assertEquals(40L, paused.downloadedBytes)
            assertEquals(100L, paused.totalBytes)
            assertEquals(TaskStage.DOWNLOADING, paused.stage)
            assertNull(paused.speedBytesPerSec)
            assertEquals(-1L, paused.etaSeconds)
            assertFalse(paused.stalled)
        }
    }

    @Test fun pausedProgressIsNeverNegative() {
        assertEquals(0.0, TaskTransitions.pause(task(progress = -1.0))!!.progress, 0.0)
    }

    @Test fun pauseFromAnyOtherStatusIsRejected() {
        for (from in others(TaskStatus.QUEUED, TaskStatus.RUNNING)) {
            assertNull("$from", TaskTransitions.pause(task(status = from)))
        }
    }

    @Test fun resumeOnlyFromPausedKeepingProgress() {
        val resumed = TaskTransitions.resume(task(status = TaskStatus.PAUSED, speedBytesPerSec = null))!!
        assertEquals(TaskStatus.QUEUED, resumed.status)
        assertEquals(0.4, resumed.progress, 0.0)
        assertEquals(40L, resumed.downloadedBytes)
        for (from in others(TaskStatus.PAUSED)) {
            assertNull("$from", TaskTransitions.resume(task(status = from)))
        }
    }

    @Test fun retryFailedKeepsProgressAndBytesAndClearsTheError() {
        val failed = task(
            status = TaskStatus.FAILED,
            errorCode = "network",
            errorMessage = "Connection dropped",
            finishedAtMs = 9L,
            speedBytesPerSec = null,
        )
        val retried = TaskTransitions.retry(failed)!!
        assertEquals(TaskStatus.QUEUED, retried.status)
        assertEquals(0.4, retried.progress, 0.0)
        assertEquals(40L, retried.downloadedBytes)
        assertEquals(100L, retried.totalBytes)
        assertNull(retried.errorCode)
        assertNull(retried.errorMessage)
        assertNull(retried.finishedAtMs)
        assertEquals(-1L, retried.etaSeconds)
    }

    @Test fun retryCanceledStartsFromZero() {
        val retried = TaskTransitions.retry(task(status = TaskStatus.CANCELED, finishedAtMs = 9L))!!
        assertEquals(TaskStatus.QUEUED, retried.status)
        assertEquals(0.0, retried.progress, 0.0)
        assertNull(retried.downloadedBytes)
        assertNull(retried.totalBytes)
        assertNull(retried.finishedAtMs)
        assertEquals(TaskStage.PREPARING, retried.stage)
    }

    @Test fun retryFromAnyOtherStatusIsRejected() {
        for (from in others(TaskStatus.FAILED, TaskStatus.CANCELED)) {
            assertNull("$from", TaskTransitions.retry(task(status = from)))
        }
    }

    @Test fun retriedProgressIsNeverNegative() {
        assertEquals(0.0, TaskTransitions.retry(task(status = TaskStatus.FAILED, progress = -1.0))!!.progress, 0.0)
    }

    @Test fun cancelStampsTheFinishTime() {
        for (from in listOf(TaskStatus.QUEUED, TaskStatus.RUNNING, TaskStatus.PAUSED)) {
            val canceled = TaskTransitions.cancel(task(status = from, stalled = true), 77L)!!
            assertEquals(TaskStatus.CANCELED, canceled.status)
            assertEquals(77L, canceled.finishedAtMs)
            assertEquals(-1L, canceled.etaSeconds)
            assertNull(canceled.speedBytesPerSec)
            assertFalse(canceled.stalled)
        }
        for (from in others(TaskStatus.QUEUED, TaskStatus.RUNNING, TaskStatus.PAUSED)) {
            assertNull("$from", TaskTransitions.cancel(task(status = from), 77L))
        }
    }

    @Test fun restartInterruptsLiveTasksOnly() {
        for (from in listOf(TaskStatus.QUEUED, TaskStatus.RUNNING)) {
            val interrupted = TaskTransitions.onRestart(task(status = from))
            assertEquals(TaskStatus.FAILED, interrupted.status)
            assertEquals("unknown", interrupted.errorCode)
            assertEquals("Interrupted", interrupted.errorMessage)
            assertEquals(0.4, interrupted.progress, 0.0)
            assertEquals(40L, interrupted.downloadedBytes)
            assertEquals(-1L, interrupted.etaSeconds)
            assertNull(interrupted.speedBytesPerSec)
        }
        for (from in others(TaskStatus.QUEUED, TaskStatus.RUNNING)) {
            val t = task(status = from)
            assertEquals("$from", t, TaskTransitions.onRestart(t))
        }
    }

    @Test fun startTakesOnlyAQueuedTaskAndKeepsAResumedPercent() {
        val started = TaskTransitions.start(task(status = TaskStatus.QUEUED, progress = 0.41, stalled = true))!!
        assertEquals(TaskStatus.RUNNING, started.status)
        assertEquals(0.41, started.progress, 0.0)
        assertEquals(TaskStage.PREPARING, started.stage)
        assertFalse(started.stalled)
        assertEquals(-1.0, TaskTransitions.start(task(status = TaskStatus.QUEUED, progress = 0.0))!!.progress, 0.0)
        for (from in others(TaskStatus.QUEUED)) assertNull("$from", TaskTransitions.start(task(status = from)))
    }

    @Test fun completeLandsFromAnyUnfinishedStatusOnly() {
        for (from in listOf(TaskStatus.RUNNING, TaskStatus.PAUSED, TaskStatus.QUEUED)) {
            val done = TaskTransitions.complete(task(status = from, errorCode = "network"), "content://m/1", 90L, 7L)!!
            assertEquals(TaskStatus.COMPLETED, done.status)
            assertEquals("content://m/1", done.savedUri)
            assertEquals(90L, done.totalBytes)
            assertEquals(7L, done.finishedAtMs)
            assertNull(done.errorCode)
            assertNull(done.speedBytesPerSec)
        }
        for (from in listOf(TaskStatus.CANCELED, TaskStatus.FAILED, TaskStatus.COMPLETED)) {
            assertNull("$from", TaskTransitions.complete(task(status = from), "content://m/1", 90L, 7L))
        }
    }

    @Test fun interruptedIsARetryableFailureStampedByTheCaller() {
        val failed = TaskTransitions.interrupted(task(stalled = true), 9L)
        assertEquals(TaskStatus.FAILED, failed.status)
        assertEquals("unknown", failed.errorCode)
        assertEquals("Interrupted", failed.errorMessage)
        assertEquals(9L, failed.finishedAtMs)
        assertEquals(-1L, failed.etaSeconds)
        assertFalse(failed.stalled)
    }

    @Test fun onlyPausedAndFailedKeepPartialFiles() {
        for (s in TaskStatus.values()) {
            assertEquals("$s", s == TaskStatus.PAUSED || s == TaskStatus.FAILED, TaskTransitions.keepsPartialFiles(s))
        }
    }
}
