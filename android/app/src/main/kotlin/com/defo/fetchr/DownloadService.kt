package com.defo.fetchr

import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.defo.fetchr.pigeon.DownloadTask
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class DownloadService : Service() {
    companion object {
        private const val TAG = "DownloadService"
        internal const val ACTION_PAUSE_ALL = "com.defo.fetchr.action.PAUSE_ALL"
        internal const val ACTION_CANCEL_ALL = "com.defo.fetchr.action.CANCEL_ALL"
        internal const val ACTION_RESUME_ALL = "com.defo.fetchr.action.RESUME_ALL"
        internal const val ACTION_RETRY = "com.defo.fetchr.action.RETRY"
        private const val EXTRA_TASK_ID = "com.defo.fetchr.extra.TASK_ID"
        private const val UPDATE_INTERVAL_MS = 500L
        // Stopping waits a moment, so a download enqueued right after the last one ended keeps the service.
        private const val IDLE_GRACE_MS = 1_500L
        private const val WAKE_LOCK_MAX_MS = 6 * 60 * 60 * 1000L

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java))
        }

        // A notification button that acts on the downloads. It starts the service as a foreground one, which a
        // paused-only or failed notification needs because no service is running then.
        internal fun actionIntent(context: Context, action: String, taskId: String? = null): PendingIntent {
            val intent = Intent(context, DownloadService::class.java).setAction(action)
            if (taskId != null) intent.putExtra(EXTRA_TASK_ID, taskId)
            return PendingIntent.getForegroundService(
                context,
                "$action:$taskId".hashCode(),
                intent,
                DownloadNotifications.IMMUTABLE_UPDATE,
            )
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var watcher: Job? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastStartId = 0
    // Tasks seen live since the service started, for the "Downloading 2 of 17" counter. Main thread only.
    private var seen: Set<String> = emptySet()

    override fun onCreate() {
        super.onCreate()
        DownloadNotifications.ensureDownloadsChannel(this)
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Fetchr:downloads")
            .apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_MAX_MS)
            }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        // Any start means a download is running or about to; a paused-only notification would be stale.
        DownloadNotifications.dismissPaused(this)
        try {
            val notification = DownloadNotifications.ongoing(this, summarize(FetchrApp.downloads.tasks.value))
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    DownloadNotifications.ONGOING_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(DownloadNotifications.ONGOING_ID, notification)
            }
        } catch (e: RuntimeException) {
            // Background-start restrictions (31+) or a missing FGS permission.
            Log.w(TAG, "Cannot enter the foreground", e)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        act(intent)
        if (watcher?.isActive != true) watcher = scope.launch { watch() }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) = timedOut(startId)

    override fun onTimeout(startId: Int, fgsType: Int) = timedOut(startId)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        scope.cancel()
        wakeLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }

    private fun timedOut(startId: Int) {
        FetchrApp.downloads.cancelAll()
        stopSelf(startId)
    }

    private fun act(intent: Intent?) {
        val downloads = FetchrApp.downloads
        when (intent?.action) {
            ACTION_CANCEL_ALL -> downloads.cancelAll()
            ACTION_PAUSE_ALL -> downloads.pauseAll()
            ACTION_RESUME_ALL -> downloads.resumeAll()
            ACTION_RETRY -> intent.getStringExtra(EXTRA_TASK_ID)?.let(downloads::retry)
        }
    }

    private suspend fun watch() {
        val manager = getSystemService(NotificationManager::class.java)
        FetchrApp.downloads.tasks.map(::summarize).distinctUntilChanged().collect { summary ->
            if (summary.live > 0) {
                manager.notify(DownloadNotifications.ONGOING_ID, DownloadNotifications.ongoing(this, summary))
                // Collect is sequential and the flow conflates, so this caps updates without dropping the last one.
                delay(UPDATE_INTERVAL_MS)
            } else {
                // A user's pause is deliberate, so it hands over to the paused notification at once.
                if (summary.paused == 0) delay(IDLE_GRACE_MS)
                settle()
            }
        }
    }

    // Nothing is running: stop, and leave a notification behind when paused tasks are waiting.
    private fun settle() {
        val summary = summarize(FetchrApp.downloads.tasks.value)
        when {
            // Something started during the grace period; the flow delivers it.
            summary.live > 0 -> return
            summary.paused > 0 -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                DownloadNotifications.paused(this, summary.paused)
            }
        }
        // stopSelf(startId) is a no-op when a newer start arrived meanwhile.
        stopSelf(lastStartId)
    }

    // Runs on Main for every task-list change, so the set is only copied when a task goes live for the first time.
    private fun summarize(tasks: List<DownloadTask>): OngoingSummary {
        val fresh = tasks.filter { it.isLive && it.id !in seen }
        if (fresh.isNotEmpty()) seen = seen + fresh.map { it.id }
        return OngoingSummary.of(tasks, seen)
    }
}
