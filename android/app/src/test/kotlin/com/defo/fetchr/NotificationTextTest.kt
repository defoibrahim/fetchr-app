package com.defo.fetchr

import com.defo.fetchr.TaskFixtures.task
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationTextTest {
    private val mib = 1_048_576L

    private fun DownloadTask.quality(q: Quality) = copy(request = request.copy(quality = q))

    private fun running(progress: Double, eta: Long = 16L, speed: Long? = (4.2 * mib).toLong()) =
        task(progress = progress, etaSeconds = eta, speedBytesPerSec = speed)

    @Test
    fun ongoingWithSpeedAndEta() {
        assertEquals("64% · 4.2 MB/s · 0:16 left", NotificationText.ongoing(running(0.64)))
    }

    @Test
    fun ongoingWithoutSpeed() {
        assertEquals("64% · 0:16 left", NotificationText.ongoing(running(0.64, speed = null)))
    }

    @Test
    fun ongoingHidesAnEtaOverADay() {
        assertEquals("64% · 4.2 MB/s", NotificationText.ongoing(running(0.64, eta = 86_401L)))
        assertEquals("64% · 4.2 MB/s · 24:00:00 left", NotificationText.ongoing(running(0.64, eta = 86_400L)))
    }

    @Test
    fun ongoingHidesAnUnknownEta() {
        assertEquals("64% · 4.2 MB/s", NotificationText.ongoing(running(0.64, eta = -1L)))
    }

    @Test
    fun ongoingShowsHoursInTheEta() {
        assertEquals("64% · 4.2 MB/s · 1:02:03 left", NotificationText.ongoing(running(0.64, eta = 3_723L)))
    }

    @Test
    fun ongoingPercentIsNotLostToFloatingPoint() {
        // 0.29 * 100 is 28.999999999999996.
        assertEquals("29% · 4.2 MB/s · 0:16 left", NotificationText.ongoing(running(0.29)))
    }

    @Test
    fun ongoingWithOnlyWhatIsKnown() {
        assertEquals("4.2 MB/s", NotificationText.ongoing(running(-1.0, eta = -1L)))
    }

    @Test
    fun ongoingStalled() {
        assertEquals("Waiting for network…", NotificationText.ongoing(running(0.64).copy(stalled = true)))
        assertEquals(
            "Waiting for network…",
            NotificationText.ongoing(running(0.0).copy(stalled = true, stage = TaskStage.PREPARING)),
        )
    }

    @Test
    fun ongoingPostProcessingNamesTheWork() {
        for (q in listOf(Quality.BEST, Quality.P1080, Quality.P720, Quality.P480)) {
            assertEquals(
                "Merging video and audio…",
                NotificationText.ongoing(task(stage = TaskStage.POST_PROCESSING).quality(q)),
            )
        }
        assertEquals(
            "Converting to MP3…",
            NotificationText.ongoing(task(stage = TaskStage.POST_PROCESSING, progress = -1.0).quality(Quality.MP3)),
        )
        assertEquals(
            "Converting to MP3 · 40%",
            NotificationText.ongoing(task(stage = TaskStage.POST_PROCESSING, progress = 0.4).quality(Quality.MP3)),
        )
        assertEquals(
            "Saving cover…",
            NotificationText.ongoing(task(stage = TaskStage.POST_PROCESSING).quality(Quality.COVER)),
        )
    }

    @Test
    fun ongoingSilenceWhileMergingIsNotAStall() {
        val merging = task(stage = TaskStage.POST_PROCESSING, stalled = true)
        assertEquals("Merging video and audio…", NotificationText.ongoing(merging))
    }

    @Test
    fun ongoingPreparing() {
        assertEquals("Starting…", NotificationText.ongoing(task(progress = -1.0, stage = TaskStage.PREPARING)))
        // A resumed task keeps its percent while it starts again.
        assertEquals("Starting…", NotificationText.ongoing(task(progress = 0.41, stage = TaskStage.PREPARING)))
        assertEquals(
            "Starting…",
            NotificationText.ongoing(
                task(progress = -1.0, etaSeconds = -1L, speedBytesPerSec = null, stage = TaskStage.DOWNLOADING),
            ),
        )
    }

    @Test
    fun counterNeedsMoreThanOneTask() {
        assertNull(NotificationText.counter(1, 1))
        assertNull(NotificationText.counter(1, 0))
        assertEquals("Downloading 2 of 17", NotificationText.counter(2, 17))
    }

    @Test
    fun savedNamesTheQualityAndSize() {
        fun saved(q: Quality, total: Long?) =
            NotificationText.saved(task(status = TaskStatus.COMPLETED, totalBytes = total).quality(q))
        assertEquals("Saved · 720p · 96 MB", saved(Quality.P720, 96 * mib))
        assertEquals("Saved · MP3 · 6.2 MB", saved(Quality.MP3, (6.2 * mib).toLong()))
        assertEquals("Saved · Cover · 240 KB", saved(Quality.COVER, 240 * 1_024L))
        assertEquals("Saved · Best · 1.2 GB", saved(Quality.BEST, (1.2 * 1_073_741_824L).toLong()))
        assertEquals("Saved · 1080p", saved(Quality.P1080, null))
        assertEquals("Saved · 480p", saved(Quality.P480, 0L))
    }

    @Test
    fun failureReasons() {
        fun failure(code: String?, progress: Double = 0.4) =
            NotificationText.failure(task(status = TaskStatus.FAILED, progress = progress, errorCode = code))
        assertEquals("Connection dropped at 41%", failure("network", 0.41))
        assertEquals("Connection dropped", failure("network", 0.0))
        assertEquals("Connection dropped", failure("network", -1.0))
        assertEquals("Video unavailable", failure("unavailable"))
        assertEquals("Private video", failure("private_video"))
        assertEquals("Site not supported", failure("unsupported_site"))
        assertEquals("Site not supported", failure("invalid_url"))
        assertEquals("Not enough storage", failure("no_storage"))
        assertEquals("Fetchr can't save files", failure("permission_denied"))
        assertEquals("yt-dlp was updating", failure("busy"))
        assertEquals("Download failed", failure("unknown"))
        assertEquals("Download failed", failure(null))
        assertEquals("Download failed", failure("something_new"))
    }

    @Test
    fun failureNeverShowsTheRawYtDlpLine() {
        val raw = task(status = TaskStatus.FAILED, errorCode = "unknown", errorMessage = "ERROR: [x] boom")
        assertEquals("Download failed", NotificationText.failure(raw))
    }

    @Test
    fun pausedCount() {
        assertEquals("1 download paused", NotificationText.paused(1))
        assertEquals("3 downloads paused", NotificationText.paused(3))
    }

    private fun at(id: String, status: TaskStatus, createdAtMs: Long) =
        task(id = id, status = status).copy(createdAtMs = createdAtMs)

    @Test
    fun summaryOfNothing() {
        val s = OngoingSummary.of(emptyList(), emptySet())
        assertEquals(OngoingSummary(live = 0, paused = 0, lead = null, position = 1, total = 0), s)
    }

    @Test
    fun summaryLeadsWithTheOldestRunningTask() {
        val newer = at("a", TaskStatus.RUNNING, 5L)
        val older = at("b", TaskStatus.RUNNING, 2L)
        val done = at("c", TaskStatus.COMPLETED, 1L)
        val s = OngoingSummary.of(listOf(newer, older, done), setOf("a", "b", "c"))
        assertEquals(older, s.lead)
        assertEquals(2, s.live)
        // One finished, so the one in progress is the second of three.
        assertEquals(2, s.position)
        assertEquals(3, s.total)
    }

    @Test
    fun summaryPrefersARunningTaskOverAnOlderQueuedOne() {
        val queued = at("q", TaskStatus.QUEUED, 1L)
        val running = at("r", TaskStatus.RUNNING, 9L)
        assertEquals(running, OngoingSummary.of(listOf(queued, running), setOf("q", "r")).lead)
    }

    @Test
    fun summaryFallsBackToTheOldestQueuedTask() {
        val first = at("q1", TaskStatus.QUEUED, 1L)
        val second = at("q2", TaskStatus.QUEUED, 2L)
        assertEquals(first, OngoingSummary.of(listOf(second, first), setOf("q1", "q2")).lead)
    }

    @Test
    fun summaryLeavesPausedTasksOutOfTheCount() {
        val paused = at("p", TaskStatus.PAUSED, 1L)
        val running = at("r", TaskStatus.RUNNING, 2L)
        val s = OngoingSummary.of(listOf(running, paused), setOf("p", "r"))
        assertEquals(1, s.live)
        assertEquals(1, s.paused)
        assertEquals(1, s.total)
        assertNull(NotificationText.counter(s.position, s.total))
    }

    @Test
    fun summaryCountsFailedCanceledAndRemovedTasksAsFinished() {
        val tasks = listOf(
            at("run", TaskStatus.RUNNING, 4L),
            at("fail", TaskStatus.FAILED, 3L),
            at("cancel", TaskStatus.CANCELED, 2L),
        )
        // "gone" was removed from the list after it finished.
        val s = OngoingSummary.of(tasks, setOf("run", "fail", "cancel", "gone"))
        assertEquals(4, s.position)
        assertEquals(4, s.total)
    }

    @Test
    fun summaryIgnoresTasksNeverSeenLive() {
        // Finished before this service started: not part of the count.
        val old = at("old", TaskStatus.COMPLETED, 1L)
        val running = at("r", TaskStatus.RUNNING, 2L)
        val s = OngoingSummary.of(listOf(running, old), setOf("r"))
        assertEquals(1, s.position)
        assertEquals(1, s.total)
    }

    @Test
    fun summaryOfOnlyPausedTasks() {
        val s = OngoingSummary.of(listOf(at("p", TaskStatus.PAUSED, 1L)), setOf("p"))
        assertEquals(0, s.live)
        assertEquals(1, s.paused)
        assertNull(s.lead)
    }
}
