package com.defo.fetchr

import com.defo.fetchr.TaskFixtures.task
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgressLineTest {
    private val mib = 1_048_576L

    @Test fun estimatedTotal() {
        val s = ProgressLine.parse("[download]  64.0% of ~184.00MiB at  4.20MiB/s ETA 00:16")!!
        assertEquals(TaskStage.DOWNLOADING, s.stage)
        assertEquals(64.0, s.percent!!, 0.001)
        assertEquals(184 * mib, s.totalBytes)
        assertEquals((184 * mib * 0.64).toLong(), s.downloadedBytes)
        assertEquals((4.20 * mib).toLong(), s.speedBytesPerSec)
        assertEquals(16L, s.etaSeconds)
    }

    @Test fun fragmentsAndExactTotal() {
        val s = ProgressLine.parse("[download]  12.5% of 10.00MiB at 1.00MiB/s ETA 00:08 (frag 3/24)")!!
        assertEquals(10 * mib, s.totalBytes)
        assertEquals((10 * mib) / 8, s.downloadedBytes)
        assertEquals(mib, s.speedBytesPerSec)
        assertEquals(8L, s.etaSeconds)
    }

    @Test fun finishedLine() {
        val s = ProgressLine.parse("[download] 100% of 184.00MiB in 00:00:44 at 4.18MiB/s")!!
        assertEquals(184 * mib, s.downloadedBytes)
        assertEquals(null, s.etaSeconds)
    }

    @Test fun unknownSpeedAndEta() {
        val s = ProgressLine.parse("[download]   0.0% of ~  1.20GiB at  Unknown B/s ETA Unknown")!!
        assertEquals((1.20 * 1_073_741_824L).toLong(), s.totalBytes)
        assertEquals(null, s.speedBytesPerSec)
        assertEquals(null, s.etaSeconds)
    }

    @Test fun hoursEta() {
        assertEquals(3723L, ProgressLine.parse("[download]   1.0% of 2.00GiB at 1.00KiB/s ETA 01:02:03")!!.etaSeconds)
    }

    @Test fun aria2c() {
        val s = ProgressLine.parse("[#2089b0 118MiB/184MiB(64%) CN:8 DL:4.2MiB ETA:1m5s]")!!
        assertEquals(TaskStage.DOWNLOADING, s.stage)
        assertEquals(64.0, s.percent!!, 0.001)
        assertEquals(118 * mib, s.downloadedBytes)
        assertEquals(184 * mib, s.totalBytes)
        assertEquals((4.2 * mib).toLong(), s.speedBytesPerSec)
        assertEquals(65L, s.etaSeconds)
    }

    @Test fun aria2cEtaUnits() {
        assertEquals(16L, ProgressLine.parse("[#a1 1MiB/2MiB(50%) CN:1 DL:1MiB ETA:16s]")!!.etaSeconds)
        assertEquals(3723L, ProgressLine.parse("[#a1 1MiB/2MiB(50%) CN:1 DL:1MiB ETA:1h2m3s]")!!.etaSeconds)
        assertEquals(null, ProgressLine.parse("[#a1 0B/2MiB(0%) CN:1 DL:0B]")!!.etaSeconds)
    }

    @Test fun postProcessing() {
        for (line in listOf(
            "[Merger] Merging formats into \"/c/x.mp4\"",
            "[ExtractAudio] Destination: /c/x.mp3",
            "[ThumbnailsConvertor] Converting thumbnail \"/c/x.webp\" to jpg",
            "[FixupM3u8] Fixing MPEG-TS in MP4 container of \"/c/x.mp4\"",
        )) {
            val s = ProgressLine.parse(line)!!
            assertEquals(TaskStage.POST_PROCESSING, s.stage)
            assertEquals(null, s.percent)
        }
    }

    @Test fun unrelatedLines() {
        assertEquals(null, ProgressLine.parse("[youtube] Qx7mT0aK3pE: Downloading webpage"))
        assertEquals(null, ProgressLine.parse("[download] Destination: /c/x.f137.mp4"))
        assertEquals(null, ProgressLine.parse(""))
    }

    @Test fun aProgressLineSetsStageBytesSpeedAndEta() {
        val stats = ProgressLine.parse("[download]  50.0% of 10.00MiB at 1.00MiB/s ETA 00:05")
        val next = task(stage = TaskStage.PREPARING, progress = -1.0, stalled = true)
            .onLine(-1f, -1L, stats).first
        assertEquals(TaskStage.DOWNLOADING, next.stage)
        assertEquals(0.5, next.progress, 0.0)
        assertEquals(5L, next.etaSeconds)
        assertEquals(5 * mib, next.downloadedBytes)
        assertEquals(10 * mib, next.totalBytes)
        assertEquals(mib, next.speedBytesPerSec)
        assertFalse(next.stalled)
    }

    @Test fun theParsedPercentWinsEvenWhenItFallsForTheNextStream() {
        val stats = ProgressLine.parse("[download]   2.0% of 1.00MiB at 1.00MiB/s ETA 00:01")
        assertEquals(0.02, task(progress = 1.0).withProgress(100f, 0L, stats).progress, 0.0)
    }

    @Test fun postProcessingStartsTheBarOverAsUnknownAndDropsSpeedAndEta() {
        val stats = ProgressLine.parse("[Merger] Merging formats into \"/c/x.mp4\"")
        val next = task(progress = 1.0, stalled = true).onLine(99f, 0L, stats).first
        assertEquals(TaskStage.POST_PROCESSING, next.stage)
        assertEquals(-1.0, next.progress, 0.0)
        assertEquals(-1L, next.etaSeconds)
        assertNull(next.speedBytesPerSec)
        assertEquals(40L, next.downloadedBytes)
        assertFalse(next.stalled)
    }

    @Test fun theLibraryRepeatingItsDownloadPercentLeavesAConversionAlone() {
        val converting = task(stage = TaskStage.POST_PROCESSING, progress = 0.3)
        assertEquals(converting, converting.withProgress(100f, 0L, null))
        assertEquals(converting, converting.withProgress(100f, 0L, ProgressLine.parse("[Metadata] Adding metadata")))
    }

    @Test fun aConversionReadsTheNewestReportBlockAgainstTheDuration() {
        val report = "out_time_us=N/A\nout_time_ms=N/A\nprogress=continue\n" +
            "out_time_us=30000000\nout_time_ms=30000000\nprogress=continue\n" +
            "out_time_us=90000000\nout_time_ms=90000000\nprogress=continue\n"
        assertEquals(0.75, ProgressLine.conversion(report, 120L)!!, 1e-9)
    }

    @Test fun aConversionWithNoReadingOrNoDurationIsUnknown() {
        assertNull(ProgressLine.conversion("", 120L))
        assertNull(ProgressLine.conversion("out_time_us=N/A\nprogress=continue\n", 120L))
        assertNull(ProgressLine.conversion("out_time_us=30000000\n", 0L))
    }

    @Test fun aConversionStaysOnTheBar() {
        assertEquals(1.0, ProgressLine.conversion("out_time_us=130000000\nprogress=end\n", 120L)!!, 0.0)
        assertEquals(0.0, ProgressLine.conversion("out_time_us=-9223372036854775807\n", 120L)!!, 0.0)
    }

    @Test fun onlyAConvertingTaskTakesTheReport() {
        val converting = task(stage = TaskStage.POST_PROCESSING, progress = -1.0)
        assertEquals(0.5, converting.withConversion(0.5)!!.progress, 0.0)
        assertNull(task(stage = TaskStage.DOWNLOADING).withConversion(0.5))
        assertNull(task(status = TaskStatus.PAUSED, stage = TaskStage.POST_PROCESSING).withConversion(0.5))
        assertNull("a tick under the step", task(stage = TaskStage.POST_PROCESSING, progress = 0.5).withConversion(0.501))
    }

    @Test fun anUnparsedLineMidDownloadKeepsTheStatsAndTheStall() {
        val before = task(stalled = true)
        val (next, alive) = before.onLine(-1f, -1L, null)
        assertEquals(before, next)
        assertFalse(alive)
    }

    @Test fun aZeroSpeedPollKeepsTheStallButMovingBytesClearIt() {
        val stalled = task(progress = 0.64, stalled = true)
        val poll = ProgressLine.parse("[download]  64.0% of 184.00MiB at 0.00B/s ETA Unknown")
        assertTrue(stalled.onLine(-1f, -1L, poll).first.stalled)
        val moving = ProgressLine.parse("[download]  64.5% of 184.00MiB at 1.00MiB/s ETA 00:40")
        val (next, alive) = stalled.onLine(-1f, -1L, moving)
        assertFalse(next.stalled)
        assertTrue(alive)
    }

    @Test fun theLibraryPercentIsOnlyTakenWhenItMovesForward() {
        val resumed = task(progress = 0.41, etaSeconds = -1L)
        assertEquals(0.41, resumed.withProgress(-1f, -1L, null).progress, 0.0)
        val moved = resumed.withProgress(60f, 12L, null)
        assertEquals(0.6, moved.progress, 0.0)
        assertEquals(12L, moved.etaSeconds)
    }

    @Test fun bytesMovingIsActivity() {
        val current = task(progress = 0.64)
        assertTrue(ProgressLine.parse("[download]  64.0% of 184.00MiB at 4.20MiB/s ETA 00:16").showsActivity(current))
        assertTrue(ProgressLine.parse("[download]  64.1% of 184.00MiB at Unknown B/s ETA Unknown").showsActivity(current))
    }

    @Test fun aStuckPollOrARetryMidDownloadIsNotActivity() {
        val current = task(progress = 0.64)
        assertFalse(ProgressLine.parse("[download]  64.0% of 184.00MiB at 0.00B/s ETA Unknown").showsActivity(current))
        assertFalse(ProgressLine.parse("[download] Got error: timed out. Retrying (1/10)...").showsActivity(current))
    }

    @Test fun outputOutsideTheTransferIsActivity() {
        assertTrue(ProgressLine.parse("[youtube] abc: Downloading webpage").showsActivity(task(stage = TaskStage.PREPARING)))
        assertTrue(ProgressLine.parse("[Merger] Merging formats into \"a.mp4\"").showsActivity(task()))
    }
}
