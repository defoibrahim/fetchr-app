package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus

internal object TaskFixtures {
    val request = DownloadRequest(
        url = "https://example.com/watch?v=abc",
        title = "A title",
        quality = Quality.P720,
        folder = "Fetchr",
        useAria2c = false,
    )

    fun task(
        id: String = "t1",
        status: TaskStatus = TaskStatus.RUNNING,
        progress: Double = 0.4,
        etaSeconds: Long = 30L,
        stage: TaskStage = TaskStage.DOWNLOADING,
        downloadedBytes: Long? = 40L,
        totalBytes: Long? = 100L,
        speedBytesPerSec: Long? = 5L,
        stalled: Boolean = false,
        errorCode: String? = null,
        errorMessage: String? = null,
        savedUri: String? = null,
        finishedAtMs: Long? = null,
    ) = DownloadTask(
        id = id,
        request = request,
        status = status,
        progress = progress,
        etaSeconds = etaSeconds,
        errorCode = errorCode,
        errorMessage = errorMessage,
        savedUri = savedUri,
        createdAtMs = 1L,
        stage = stage,
        downloadedBytes = downloadedBytes,
        totalBytes = totalBytes,
        speedBytesPerSec = speedBytesPerSec,
        stalled = stalled,
        finishedAtMs = finishedAtMs,
    )
}
