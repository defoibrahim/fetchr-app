package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class TaskCodecTest {
    private val errorCodes = listOf(
        "unsupported_site", "invalid_url", "private_video", "unavailable", "network", "no_storage", "busy", "unknown",
    )

    private val request = DownloadRequest(
        url = "https://example.com/watch?v=abc",
        title = "A \"quoted\" title\nwith newline",
        thumbnail = "https://example.com/t.jpg",
        quality = Quality.P720,
        folder = "Fetchr",
        useAria2c = true,
    )

    private fun task(
        id: String = "t1",
        status: TaskStatus = TaskStatus.COMPLETED,
        progress: Double = 1.0,
        etaSeconds: Long = 0,
        errorCode: String? = null,
        errorMessage: String? = null,
        savedUri: String? = "content://media/external/video/media/42",
        request: DownloadRequest = this.request,
        stage: TaskStage = TaskStage.PREPARING,
        downloadedBytes: Long? = null,
        totalBytes: Long? = null,
        speedBytesPerSec: Long? = null,
        stalled: Boolean = false,
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
        createdAtMs = 1_760_000_000_123L,
        stage = stage,
        downloadedBytes = downloadedBytes,
        totalBytes = totalBytes,
        speedBytesPerSec = speedBytesPerSec,
        stalled = stalled,
        finishedAtMs = finishedAtMs,
    )

    @Test
    fun roundTripsEveryField() {
        val tasks = listOf(
            task(),
            task(
                id = "t2",
                status = TaskStatus.FAILED,
                progress = 0.37,
                etaSeconds = -1,
                errorCode = "private_video",
                errorMessage = "Private video",
                savedUri = null,
                request = request.copy(thumbnail = null, quality = Quality.MP3, useAria2c = false),
            ),
            task(id = "t3", status = TaskStatus.CANCELED, progress = -1.0, etaSeconds = -1, savedUri = null),
        )

        assertEquals(tasks, TaskCodec.decode(TaskCodec.encode(tasks)))
    }

    @Test
    fun roundTripsACoverTask() {
        val cover = task(
            id = "cover",
            savedUri = "content://media/external/images/media/7",
            request = request.copy(quality = Quality.COVER, useAria2c = false),
        )

        val decoded = TaskCodec.decode(TaskCodec.encode(listOf(cover))).single()

        assertEquals(cover, decoded)
        assertEquals(Quality.COVER, decoded.request.quality)
    }

    @Test
    fun roundTripsEveryEnumValue() {
        val tasks = Quality.values().mapIndexed { i, q ->
            task(id = "q$i", request = request.copy(quality = q))
        } + errorCodes.mapIndexed { i, c ->
            task(id = "e$i", status = TaskStatus.FAILED, errorCode = c, errorMessage = "m", savedUri = null)
        }

        assertEquals(tasks, TaskCodec.decode(TaskCodec.encode(tasks)))
    }

    @Test
    fun emptyListRoundTrips() {
        assertEquals(emptyList<DownloadTask>(), TaskCodec.decode(TaskCodec.encode(emptyList())))
    }

    @Test
    fun keepsOrder() {
        val tasks = listOf(task(id = "c"), task(id = "a"), task(id = "b"))

        assertEquals(listOf("c", "a", "b"), TaskCodec.decode(TaskCodec.encode(tasks)).map { it.id })
    }

    @Test
    fun nullOptionalsStayNull() {
        val bare = task(
            status = TaskStatus.FAILED,
            savedUri = null,
            request = request.copy(thumbnail = null),
        )

        val decoded = TaskCodec.decode(TaskCodec.encode(listOf(bare))).single()

        assertNull(decoded.request.thumbnail)
        assertNull(decoded.errorCode)
        assertNull(decoded.errorMessage)
        assertNull(decoded.savedUri)
    }

    @Test
    fun queuedAndRunningLoadAsInterruptedFailures() {
        val tasks = listOf(
            task(id = "q", status = TaskStatus.QUEUED, progress = 0.0, etaSeconds = -1, savedUri = null),
            task(id = "r", status = TaskStatus.RUNNING, progress = 0.5, etaSeconds = 30, savedUri = null),
        )

        val decoded = TaskCodec.decode(TaskCodec.encode(tasks))

        assertEquals(listOf("q", "r"), decoded.map { it.id })
        decoded.forEach {
            assertEquals(TaskStatus.FAILED, it.status)
            assertEquals("unknown", it.errorCode)
            assertEquals("Interrupted", it.errorMessage)
            assertEquals(request, it.request)
        }
    }

    @Test
    fun pausedTaskKeepsItsProgressAndBytes() {
        val paused = task(
            id = "p",
            status = TaskStatus.PAUSED,
            progress = 0.42,
            savedUri = null,
            stage = TaskStage.DOWNLOADING,
            downloadedBytes = 44_040_192L,
            totalBytes = 104_857_600L,
            finishedAtMs = 1_760_000_100_000L,
        )

        val decoded = TaskCodec.decode(TaskCodec.encode(listOf(paused))).single()

        assertEquals(paused, decoded)
        assertEquals(TaskStatus.PAUSED, decoded.status)
    }

    @Test
    fun everyStageAndFinishTimeRoundTrips() {
        val tasks = TaskStage.values().mapIndexed { i, stage ->
            task(
                id = "s$i",
                status = TaskStatus.FAILED,
                savedUri = null,
                errorCode = "network",
                errorMessage = "m",
                stage = stage,
                downloadedBytes = 1_000L * i,
                totalBytes = 5_000_000_000L,
                speedBytesPerSec = 2_500_000L,
                finishedAtMs = 1_760_000_200_000L + i,
            )
        }

        assertEquals(tasks, TaskCodec.decode(TaskCodec.encode(tasks)))
    }

    @Test
    fun requestMetadataRoundTrips() {
        val withMeta = task(
            request = request.copy(
                uploader = "Blender",
                durationSeconds = 635L,
                playlistTitle = "Shorts",
                playlistIndex = 2L,
                playlistCount = 17L,
            ),
        )

        assertEquals(withMeta, TaskCodec.decode(TaskCodec.encode(listOf(withMeta))).single())
    }

    @Test
    fun jsonWrittenBeforeTheNewKeysDecodesWithDefaults() {
        val old = """[{"id":"old","status":"COMPLETED","progress":1,"etaSeconds":0,
            "savedUri":"content://media/external/video/media/9","createdAtMs":1760000000123,
            "request":{"url":"https://example.com/a","title":"Old","quality":"P720","folder":"Fetchr","useAria2c":false}}]"""

        val decoded = TaskCodec.decode(old).single()

        assertEquals(TaskStatus.COMPLETED, decoded.status)
        assertEquals(TaskStage.PREPARING, decoded.stage)
        assertNull(decoded.downloadedBytes)
        assertNull(decoded.totalBytes)
        assertNull(decoded.speedBytesPerSec)
        assertNull(decoded.finishedAtMs)
        assertFalse(decoded.stalled)
        assertNull(decoded.request.uploader)
        assertNull(decoded.request.durationSeconds)
        assertNull(decoded.request.playlistTitle)
        assertNull(decoded.request.playlistIndex)
        assertNull(decoded.request.playlistCount)
    }

    @Test
    fun stalledIsNeverPersisted() {
        val stalled = task(status = TaskStatus.PAUSED, savedUri = null, stalled = true)

        val json = TaskCodec.encode(listOf(stalled))

        assertFalse(json.contains("stalled"))
        assertFalse(TaskCodec.decode(json).single().stalled)
    }

    @Test
    fun interruptedTaskKeepsItsBytesSoRetryCanResume() {
        val running = task(
            status = TaskStatus.RUNNING,
            progress = 0.5,
            savedUri = null,
            stage = TaskStage.DOWNLOADING,
            downloadedBytes = 52_428_800L,
            totalBytes = 104_857_600L,
        )

        val decoded = TaskCodec.decode(TaskCodec.encode(listOf(running))).single()

        assertEquals(TaskStatus.FAILED, decoded.status)
        assertEquals(0.5, decoded.progress, 0.0)
        assertEquals(52_428_800L, decoded.downloadedBytes)
        assertEquals(104_857_600L, decoded.totalBytes)
    }

    @Test
    fun finishedStatusesAreNotRewritten() {
        val tasks = listOf(
            task(id = "ok", status = TaskStatus.COMPLETED),
            task(id = "no", status = TaskStatus.CANCELED, savedUri = null),
        )

        assertEquals(tasks, TaskCodec.decode(TaskCodec.encode(tasks)))
    }

    @Test
    fun corruptInputLoadsAsEmpty() {
        assertEquals(emptyList<DownloadTask>(), TaskCodec.decode(""))
        assertEquals(emptyList<DownloadTask>(), TaskCodec.decode("{not json"))
    }

    @Test
    fun malformedTaskIsSkippedAndTheRestLoad() {
        val good = TaskCodec.encode(listOf(task(id = "good")))
        val withBad = good.dropLast(1) + """,{"id":"bad","status":"NOPE"}]"""

        assertEquals(listOf("good"), TaskCodec.decode(withBad).map { it.id })
    }
}
