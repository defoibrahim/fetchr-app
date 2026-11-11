package com.defo.fetchr

import com.defo.fetchr.TaskFixtures.task
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.TaskStage
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgressChangedTest {
    private fun at(
        progress: Double,
        eta: Long = 30L,
        stage: TaskStage = TaskStage.DOWNLOADING,
        stalled: Boolean = false,
    ): DownloadTask = task(progress = progress, etaSeconds = eta, stage = stage, stalled = stalled)

    @Test
    fun tinyMoveWithSameEtaIsSkipped() {
        assertFalse(progressChanged(at(0.500), at(0.504)))
        assertFalse(progressChanged(at(-1.0, eta = -1L), at(-1.0, eta = -1L)))
    }

    @Test
    fun halfAPercentMovePasses() {
        assertTrue(progressChanged(at(0.50), at(0.51)))
        assertTrue(progressChanged(at(0.51), at(0.50)))
    }

    @Test
    fun newEtaAlwaysPasses() {
        assertTrue(progressChanged(at(0.500), at(0.501, eta = 29L)))
        assertTrue(progressChanged(at(0.5, eta = -1L), at(0.5, eta = 12L)))
    }

    @Test
    fun enteringOrLeavingUnknownAlwaysPasses() {
        assertTrue(progressChanged(at(-1.0, eta = -1L), at(0.0, eta = -1L)))
        assertTrue(progressChanged(at(0.001, eta = 5L), at(-1.0, eta = 5L)))
    }

    @Test
    fun aNewStagePassesEvenWhenTheBarDidNotMove() {
        assertTrue(progressChanged(at(1.0), at(1.0, stage = TaskStage.POST_PROCESSING)))
    }

    @Test
    fun stallingOrRecoveringPassesEvenWhenTheBarDidNotMove() {
        assertTrue(progressChanged(at(0.5), at(0.5, stalled = true)))
        assertTrue(progressChanged(at(0.5, stalled = true), at(0.5)))
    }
}
