package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus

// Every string the download notifications show. Pure, so the copy is tested without a device.
internal object NotificationText {
    private const val ETA_HIDDEN_AFTER_SECONDS = 24 * 60 * 60L
    const val STARTING = "Starting…"

    // 0..100. The nudge keeps 0.29 * 100 = 28.999999999999996 from reading 28%, and flooring never shows 100% early.
    fun percent(progress: Double): Int = (progress * 100 + 1e-6).toInt().coerceIn(0, 100)

    fun ongoing(task: DownloadTask): String = when {
        task.stage == TaskStage.POST_PROCESSING -> when (task.request.quality.mediaKind) {
            MediaKind.AUDIO -> if (task.progress >= 0) "Converting to MP3 · ${percent(task.progress)}%" else "Converting to MP3…"
            MediaKind.IMAGE -> "Saving cover…"
            MediaKind.VIDEO -> "Merging video and audio…"
        }
        task.stalled -> "Waiting for network…"
        task.stage == TaskStage.PREPARING -> STARTING
        else -> listOfNotNull(
            if (task.progress >= 0) "${percent(task.progress)}%" else null,
            task.speedBytesPerSec?.takeIf { it > 0 }?.let(Bytes::speed),
            task.etaSeconds.takeIf { it in 0..ETA_HIDDEN_AFTER_SECONDS }?.let { "${clock(it)} left" },
        ).joinToString(" · ").ifEmpty { STARTING }
    }

    // current is the 1-based place of the task in progress, so the caller passes finished + 1.
    fun counter(current: Int, total: Int): String? = if (total > 1) "Downloading $current of $total" else null

    fun saved(task: DownloadTask): String = listOfNotNull(
        "Saved",
        task.request.quality.shortLabel,
        task.totalBytes?.takeIf { it > 0 }?.let(Bytes::format),
    ).joinToString(" · ")

    // Never the raw yt-dlp line: it can carry a URL.
    fun failure(task: DownloadTask): String = when (task.errorCode) {
        "network" -> percent(task.progress).let { if (it > 0) "Connection dropped at $it%" else "Connection dropped" }
        "unavailable" -> "Video unavailable"
        "private_video" -> "Private video"
        "unsupported_site", "invalid_url" -> "Site not supported"
        "no_storage" -> "Not enough storage"
        "permission_denied" -> "Fetchr can't save files"
        "busy" -> "yt-dlp was updating"
        else -> "Download failed"
    }

    fun paused(count: Int): String = if (count == 1) "1 download paused" else "$count downloads paused"

    private fun clock(seconds: Long): String {
        val hours = seconds / 3_600
        val minutes = (seconds % 3_600) / 60
        val rest = (seconds % 60).toString().padStart(2, '0')
        return if (hours > 0) "$hours:${minutes.toString().padStart(2, '0')}:$rest" else "$minutes:$rest"
    }

    // The pill text of the Dart Quality enum.
    private val Quality.shortLabel: String
        get() = when (this) {
            Quality.BEST -> "Best"
            Quality.P1080 -> "1080p"
            Quality.P720 -> "720p"
            Quality.P480 -> "480p"
            Quality.MP3 -> "MP3"
            Quality.COVER -> "Cover"
        }
}

// What the foreground notification shows for a task list. live and paused count tasks; position and total count
// the tasks seen live since the service started, minus the paused ones, who are neither done nor running.
internal data class OngoingSummary(
    val live: Int,
    val paused: Int,
    val lead: DownloadTask?,
    val position: Int,
    val total: Int,
) {
    companion object {
        fun of(tasks: List<DownloadTask>, seen: Set<String>): OngoingSummary {
            val live = tasks.filter { it.isLive }
            // A seen task is finished unless it is still unfinished: gone from the list counts as finished.
            val finished = seen.size - tasks.count { it.id in seen && TaskTransitions.isUnfinished(it) }
            return OngoingSummary(
                live = live.size,
                paused = tasks.count { it.status == TaskStatus.PAUSED },
                lead = live.filter { it.status == TaskStatus.RUNNING }.ifEmpty { live }.minByOrNull { it.createdAtMs },
                position = finished + 1,
                total = finished + live.size,
            )
        }
    }
}
