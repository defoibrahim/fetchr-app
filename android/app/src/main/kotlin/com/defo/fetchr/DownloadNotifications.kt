package com.defo.fetchr

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object DownloadNotifications {
    private const val TAG = "DownloadNotifications"
    private const val DOWNLOADS_CHANNEL = "downloads"
    private const val RESULTS_CHANNEL = "download_results"
    internal const val ONGOING_ID = 4201
    private const val PAUSED_ID = 4202
    private const val DOWNLOADS_LINK = "fetchr://app/downloads"
    private val ERROR_COLOR = 0xFFFF9147.toInt()
    internal const val IMMUTABLE_UPDATE = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

    // finished() fetches a thumbnail, which must not hold the download slot of the task that just ended.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    internal fun ensureDownloadsChannel(context: Context) {
        NotificationManagerCompat.from(context).createNotificationChannel(
            NotificationChannelCompat.Builder(DOWNLOADS_CHANNEL, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName("Downloads")
                .build(),
        )
    }

    // The foreground notification: the oldest running task, its numbers and the batch counter.
    internal fun ongoing(context: Context, summary: OngoingSummary): Notification {
        val lead = summary.lead
        // Unknown while starting, merging, or converting until ffmpeg's first report: an indeterminate bar.
        val percent = lead
            ?.takeIf { it.stage != TaskStage.PREPARING && it.progress >= 0 }
            ?.let { NotificationText.percent(it.progress) }
        val intents = ongoingIntents(context.applicationContext)
        return base(context, DOWNLOADS_CHANNEL)
            .setContentTitle(lead?.request?.title ?: "Downloading")
            .setContentText(lead?.let(NotificationText::ongoing) ?: NotificationText.STARTING)
            .setSubText(NotificationText.counter(summary.position, summary.total))
            .setProgress(100, percent ?: 0, percent == null)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(intents.open)
            .addAction(0, "Pause all", intents.pauseAll)
            .addAction(0, if (summary.total > 1) "Cancel all" else "Cancel", intents.cancelAll)
            .build()
    }

    private class OngoingIntents(val open: PendingIntent, val pauseAll: PendingIntent, val cancelAll: PendingIntent)

    // Built once: the ongoing notification is rebuilt on every progress update, and each PendingIntent is an IPC.
    @Volatile private var ongoingIntents: OngoingIntents? = null

    private fun ongoingIntents(context: Context): OngoingIntents = ongoingIntents ?: OngoingIntents(
        deepLink(context, DOWNLOADS_LINK),
        DownloadService.actionIntent(context, DownloadService.ACTION_PAUSE_ALL),
        DownloadService.actionIntent(context, DownloadService.ACTION_CANCEL_ALL),
    ).also { ongoingIntents = it }

    // Shown after the service stops with only paused tasks left; swiping it away loses nothing.
    @SuppressLint("MissingPermission")
    internal fun paused(context: Context, count: Int) {
        if (!canPost(context)) return
        val notification = base(context, DOWNLOADS_CHANNEL)
            .setContentTitle("Downloads paused")
            .setContentText(NotificationText.paused(count))
            .setShowWhen(false)
            .setAutoCancel(true)
            .setContentIntent(deepLink(context, DOWNLOADS_LINK))
            .addAction(0, "Resume all", DownloadService.actionIntent(context, DownloadService.ACTION_RESUME_ALL))
            .build()
        NotificationManagerCompat.from(context).notify(PAUSED_ID, notification)
    }

    internal fun dismissPaused(context: Context) = NotificationManagerCompat.from(context).cancel(PAUSED_ID)

    internal fun dismissResult(context: Context, taskId: String) =
        NotificationManagerCompat.from(context).cancel(taskId.hashCode())

    fun finished(context: Context, task: DownloadTask) {
        if (task.status != TaskStatus.COMPLETED && task.status != TaskStatus.FAILED) return
        if (!canPost(context)) return
        val app = context.applicationContext
        scope.launch {
            try {
                post(app, task)
            } catch (e: RuntimeException) {
                Log.w(TAG, "Could not post the result notification", e)
            }
        }
    }

    // Permission is only needed from 33; before that notify() needs none.
    private fun canPost(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun base(context: Context, channel: String): NotificationCompat.Builder =
        NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_fetchr)
            .setColor(NativePrefs.accent(context))

    @SuppressLint("MissingPermission")
    private suspend fun post(context: Context, task: DownloadTask) {
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannel(
            NotificationChannelCompat.Builder(RESULTS_CHANNEL, NotificationManagerCompat.IMPORTANCE_DEFAULT)
                .setName("Download results")
                .build(),
        )
        val builder = base(context, RESULTS_CHANNEL)
            .setContentTitle(task.request.title)
            .setAutoCancel(true)
        if (task.status == TaskStatus.COMPLETED) complete(context, task, builder) else failed(context, task, builder)
        // The id is the task's, so a retried failure is replaced by its result.
        manager.notify(task.id.hashCode(), builder.build())
    }

    private suspend fun complete(context: Context, task: DownloadTask, builder: NotificationCompat.Builder) {
        builder
            .setContentText(NotificationText.saved(task))
            .setSubText("Download complete")
            .setLargeIcon(largeIcon(context, task))
        val uri = task.savedUri?.let(Uri::parse)
        if (uri == null) {
            builder.setContentIntent(deepLink(context, DOWNLOADS_LINK))
            return
        }
        // The saved file is mp4, mp3 or jpg unless yt-dlp had to keep a single-file format, so ask the provider first.
        val mime = runCatching { context.contentResolver.getType(uri) }.getOrNull()
            ?: task.request.quality.mediaKind.defaultMime
        // The in-app player has nothing to show for a cover, so it opens in the viewer app.
        val isCover = task.request.quality.mediaKind == MediaKind.IMAGE
        val open = if (isCover) viewFile(context, task, uri, mime) else deepLink(context, playerLink(task, uri))
        builder
            .setContentIntent(open)
            .addAction(0, if (isCover) "Open" else "Play", open)
            .addAction(0, "Share", share(context, task, uri, mime))
    }

    private fun failed(context: Context, task: DownloadTask, builder: NotificationCompat.Builder) {
        val downloads = deepLink(context, DOWNLOADS_LINK)
        builder
            .setColor(ERROR_COLOR)
            .setContentText(NotificationText.failure(task))
            .setSubText("Download failed")
            .setContentIntent(downloads)
        // Retrying cannot help when Android refuses the write; the fix is in the app's settings.
        if (task.errorCode == "permission_denied") {
            builder.addAction(0, "Open settings", appSettings(context))
        } else {
            builder.addAction(
                0,
                "Retry",
                DownloadService.actionIntent(context, DownloadService.ACTION_RETRY, task.id),
            )
        }
        builder.addAction(0, "Open Downloads", downloads)
    }

    // The saved file's own frame first, so a batch never downloads a picture per finished item; the request's url
    // covers audio and, before API 29, covers.
    private suspend fun largeIcon(context: Context, task: DownloadTask): Bitmap? =
        task.savedUri
            ?.let { MediaLibrary.thumbnail(context, it, NotificationThumbnail.MAX_PX, NotificationThumbnail.MAX_PX) }
            ?.let(BitmapFactory::decodeFile)
            ?: NotificationThumbnail.fetch(task.request.thumbnail)

    // The key keeps one PendingIntent per action and target.
    private fun activity(context: Context, key: String, intent: Intent): PendingIntent =
        PendingIntent.getActivity(
            context,
            key.hashCode(),
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            IMMUTABLE_UPDATE,
        )

    private fun deepLink(context: Context, link: String): PendingIntent = deepLink(context, Uri.parse(link))

    private fun deepLink(context: Context, uri: Uri): PendingIntent =
        activity(context, uri.toString(), Intent(Intent.ACTION_VIEW, uri, context, MainActivity::class.java))

    private fun playerLink(task: DownloadTask, uri: Uri): Uri =
        Uri.Builder()
            .scheme("fetchr")
            .authority("app")
            .appendPath("player")
            .appendQueryParameter("uri", uri.toString())
            .appendQueryParameter("title", task.request.title)
            .build()

    private fun viewFile(context: Context, task: DownloadTask, uri: Uri, mime: String): PendingIntent =
        activity(context, "view:${task.id}", MediaLibrary.viewIntent(uri, mime))

    private fun share(context: Context, task: DownloadTask, uri: Uri, mime: String): PendingIntent =
        activity(context, "share:${task.id}", MediaLibrary.shareIntent(uri, mime))

    private fun appSettings(context: Context): PendingIntent =
        activity(
            context,
            "settings",
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
        )
}
