package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus

internal data class ProgressStats(
    val stage: TaskStage,
    val percent: Double? = null, // 0..100
    val downloadedBytes: Long? = null,
    val totalBytes: Long? = null,
    val speedBytesPerSec: Long? = null,
    val etaSeconds: Long? = null,
)

internal object ProgressLine {
    private const val SIZE = """(\d+(?:\.\d+)?)\s*([KMGT]?i?B)"""

    private val ytPercent = Regex("""^\[download\]\s+(\d+(?:\.\d+)?)%""")
    private val ytTotal = Regex("""\bof\s+~?\s*$SIZE""")
    private val ytSpeed = Regex("""\bat\s+$SIZE/s""")
    private val ytEta = Regex("""\bETA\s+(\d+(?::\d+){1,2})""")
    private val aria = Regex("""\[#\w+\s+$SIZE/$SIZE\((\d+)%\)""")
    private val ariaSpeed = Regex("""\bDL:$SIZE""")
    private val ariaEta = Regex("""\bETA:((?:\d+[dhms])+)""")
    private val ariaEtaPart = Regex("""(\d+)([dhms])""")
    private val postProcessor =
        Regex("""^\[(?:Merger|ExtractAudio|ThumbnailsConvertor|VideoConvertor|VideoRemuxer|Fixup\w+|Metadata|EmbedThumbnail)]""")
    private val ffmpegTime = Regex("""\bout_time_(?:us|ms)=(-?\d+)""")

    // Null for a line that says nothing about progress or stage.
    fun parse(line: String): ProgressStats? =
        ytDlp(line) ?: aria2c(line)
            ?: if (postProcessor.containsMatchIn(line)) ProgressStats(TaskStage.POST_PROCESSING) else null

    // 0..1 from ffmpeg's -progress report: key=value blocks, newest last. out_time_us, and the older out_time_ms
    // that is microseconds too, is how much output is written; N/A before the first frame.
    fun conversion(report: String, durationSeconds: Long): Double? {
        if (durationSeconds <= 0) return null
        val micros = ffmpegTime.findAll(report).lastOrNull()?.groupValues?.get(1)?.toLongOrNull() ?: return null
        return (micros / (durationSeconds * 1e6)).coerceIn(0.0, 1.0)
    }

    private fun ytDlp(line: String): ProgressStats? {
        val percent = ytPercent.find(line)?.groupValues?.get(1)?.toDouble() ?: return null
        val total = ytTotal.find(line)?.let { bytes(it.groupValues[1], it.groupValues[2]) }
        return ProgressStats(
            stage = TaskStage.DOWNLOADING,
            percent = percent,
            downloadedBytes = total?.let { (it * (percent / 100.0)).toLong() },
            totalBytes = total,
            speedBytesPerSec = ytSpeed.find(line)?.let { bytes(it.groupValues[1], it.groupValues[2]) },
            etaSeconds = ytEta.find(line)?.groupValues?.get(1)?.split(':')?.fold(0L) { acc, p -> acc * 60 + p.toLong() },
        )
    }

    private fun aria2c(line: String): ProgressStats? {
        val m = aria.find(line)?.groupValues ?: return null
        return ProgressStats(
            stage = TaskStage.DOWNLOADING,
            percent = m[5].toDouble(),
            downloadedBytes = bytes(m[1], m[2]),
            totalBytes = bytes(m[3], m[4]),
            speedBytesPerSec = ariaSpeed.find(line)?.let { bytes(it.groupValues[1], it.groupValues[2]) },
            etaSeconds = ariaEta.find(line)?.groupValues?.get(1)?.let(::ariaSeconds),
        )
    }

    private fun ariaSeconds(eta: String): Long = ariaEtaPart.findAll(eta).sumOf { part ->
        val n = part.groupValues[1].toLong()
        when (part.groupValues[2]) {
            "d" -> n * 86_400
            "h" -> n * 3_600
            "m" -> n * 60
            else -> n
        }
    }

    private fun bytes(value: String, unit: String): Long {
        val scale = when (unit.first()) {
            'K' -> 1L shl 10
            'M' -> 1L shl 20
            'G' -> 1L shl 30
            'T' -> 1L shl 40
            else -> 1L
        }
        return (value.toDouble() * scale).toLong()
    }
}

// For the stall watchdog: bytes moving, or output outside the byte transfer (extraction while preparing). A retry
// warning, or an aria2c poll at 0 B/s, in the middle of a download is not a sign of life.
internal fun ProgressStats?.showsActivity(current: DownloadTask): Boolean = when {
    this == null -> current.stage != TaskStage.DOWNLOADING
    stage != TaskStage.DOWNLOADING -> true
    (speedBytesPerSec ?: 0L) > 0L -> true
    // Percent lines step by 0.1; the margin absorbs the rounding of progress = percent / 100.
    else -> percent != null && percent - current.progress * 100 > 0.05
}

// The library reports -1 until its first percent line, which would wipe the percent a resumed task keeps,
// so its own reading is only taken when the bar moves forward.
internal fun DownloadTask.withProgress(libraryPercent: Float, libraryEta: Long, stats: ProgressStats?): DownloadTask {
    val percent = stats?.percent
    if (percent == null && (stats?.stage ?: stage) == TaskStage.POST_PROCESSING) {
        // The bytes are in, and the library repeats its last download percent on every later line. The bar starts
        // over as unknown, and only ffmpeg's report moves it (withConversion).
        return if (stage == TaskStage.POST_PROCESSING) {
            this
        } else {
            copy(stage = TaskStage.POST_PROCESSING, progress = -1.0, etaSeconds = -1L, speedBytesPerSec = null)
        }
    }
    val own = if (libraryPercent < 0f) -1.0 else (libraryPercent / 100.0).coerceIn(0.0, 1.0)
    val forward = if (own > progress) copy(progress = own, etaSeconds = libraryEta) else this
    return when {
        stats == null || percent == null -> forward
        else -> copy(
            stage = stats.stage,
            progress = (percent / 100.0).coerceIn(0.0, 1.0),
            etaSeconds = stats.etaSeconds ?: -1L,
            downloadedBytes = stats.downloadedBytes,
            totalBytes = stats.totalBytes,
            speedBytesPerSec = stats.speedBytesPerSec,
        )
    }
}

// A line that shows the download alive resets the stall watchdog and clears the stall flag; any other line leaves
// both, so a retry warning or a 0 B/s poll never flips "Waiting for network…" off between watchdog checks.
internal fun DownloadTask.onLine(libraryPercent: Float, libraryEta: Long, stats: ProgressStats?): Pair<DownloadTask, Boolean> {
    val alive = stats.showsActivity(this)
    val next = withProgress(libraryPercent, libraryEta, stats)
    return (if (alive) next.copy(stalled = false) else next) to alive
}

// ffmpeg's reading while the task converts; null when it is not converting or the bar would barely move.
internal fun DownloadTask.withConversion(progress: Double): DownloadTask? =
    copy(progress = progress).takeIf {
        status == TaskStatus.RUNNING && stage == TaskStage.POST_PROCESSING && progressChanged(this, it)
    }
