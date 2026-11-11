package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus

// Each rule returns null when the task is not in a status it applies to.
internal object TaskTransitions {
    // A paused or re-queued task shows its percent, so an unknown one (-1) reads as 0.
    private fun DownloadTask.knownProgress() = progress.coerceAtLeast(0.0)

    // Nothing is transferring any more.
    private fun DownloadTask.halted() = copy(etaSeconds = -1L, speedBytesPerSec = null, stalled = false)

    fun isUnfinished(t: DownloadTask): Boolean = t.isLive || t.status == TaskStatus.PAUSED

    // A resumed task keeps the percent it stopped at until the first line moves it.
    fun start(t: DownloadTask): DownloadTask? =
        if (t.status == TaskStatus.QUEUED) {
            t.halted().copy(
                status = TaskStatus.RUNNING,
                progress = if (t.progress > 0) t.progress else -1.0,
                stage = TaskStage.PREPARING,
            )
        } else {
            null
        }

    // A pause or a resume may have moved the task while the file was saved; a cancel or a remove keeps its outcome.
    fun complete(t: DownloadTask, savedUri: String, bytes: Long, nowMs: Long): DownloadTask? =
        if (isUnfinished(t)) {
            t.halted().copy(
                status = TaskStatus.COMPLETED,
                progress = 1.0,
                etaSeconds = 0L,
                downloadedBytes = bytes,
                totalBytes = bytes,
                errorCode = null,
                errorMessage = null,
                savedUri = savedUri,
                finishedAtMs = nowMs,
            )
        } else {
            null
        }

    fun fail(t: DownloadTask, code: String, message: String?, finishedAtMs: Long?): DownloadTask =
        t.halted().copy(status = TaskStatus.FAILED, errorCode = code, errorMessage = message, finishedAtMs = finishedAtMs)

    fun pause(t: DownloadTask): DownloadTask? =
        if (t.isLive) t.halted().copy(status = TaskStatus.PAUSED, progress = t.knownProgress()) else null

    fun resume(t: DownloadTask): DownloadTask? =
        if (t.status == TaskStatus.PAUSED) t.copy(status = TaskStatus.QUEUED) else null

    fun retry(t: DownloadTask): DownloadTask? = when (t.status) {
        TaskStatus.FAILED -> requeued(t).copy(progress = t.knownProgress())
        TaskStatus.CANCELED ->
            requeued(t).copy(progress = 0.0, downloadedBytes = null, totalBytes = null, stage = TaskStage.PREPARING)
        else -> null
    }

    fun cancel(t: DownloadTask, nowMs: Long): DownloadTask? =
        if (isUnfinished(t)) t.halted().copy(status = TaskStatus.CANCELED, finishedAtMs = nowMs) else null

    // A process that died mid-download cannot go on; the task is a retryable failure that keeps its bytes.
    fun onRestart(t: DownloadTask): DownloadTask = if (t.isLive) interrupted(t, t.finishedAtMs) else t

    // A run that lost its process: a restart, or a late destroyProcessById aimed at the attempt before.
    fun interrupted(t: DownloadTask, finishedAtMs: Long?): DownloadTask = fail(t, "unknown", "Interrupted", finishedAtMs)

    fun keepsPartialFiles(status: TaskStatus): Boolean =
        status == TaskStatus.PAUSED || status == TaskStatus.FAILED

    private fun requeued(t: DownloadTask) = t.halted().copy(
        status = TaskStatus.QUEUED,
        errorCode = null,
        errorMessage = null,
        savedUri = null,
        finishedAtMs = null,
    )
}
