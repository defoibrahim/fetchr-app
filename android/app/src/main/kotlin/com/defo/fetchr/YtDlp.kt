package com.defo.fetchr

import android.app.Application
import android.content.Context
import android.util.Log
import com.defo.fetchr.pigeon.FetchrError
import com.defo.fetchr.pigeon.YtDlpStatus
import com.yausername.aria2c.Aria2c
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

internal class RunGate {
    private val lock = Mutex()
    private var active = 0
    private var swap: CompletableDeferred<Unit>? = null

    suspend fun enter() {
        while (true) {
            val pending = lock.withLock {
                val current = swap
                if (current == null) active++
                current
            } ?: return
            pending.await()
        }
    }

    suspend fun leave() {
        withContext(NonCancellable) { lock.withLock { active-- } }
    }

    suspend fun beginSwap() {
        lock.withLock {
            if (active > 0 || swap != null) {
                throw FetchrError("busy", "Finish or cancel downloads before updating yt-dlp.", null)
            }
            swap = CompletableDeferred<Unit>()
        }
    }

    suspend fun endSwap() {
        withContext(NonCancellable) {
            lock.withLock {
                swap?.complete(Unit)
                swap = null
            }
        }
    }
}

object YtDlp {
    private const val TAG = "YtDlp"
    private const val KEY_CHECKED_AT = "ytdlp_checked_at"
    private const val KEY_AUTO_UPDATE = "ytdlp_auto_update"
    private const val STARTUP_WAIT_MS = 5_000L

    val ready: CompletableDeferred<Unit> = CompletableDeferred()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val gate = RunGate()

    // Set before the job runs, so a status() that sees ready never misses a startup update.
    @Volatile
    private var startupUpdate: Job? = null

    fun start(app: Application) {
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                YoutubeDL.getInstance().init(app)
                FFmpeg.getInstance().init(app)
                Aria2c.getInstance().init(app)
            } catch (t: Throwable) {
                Log.e(TAG, "yt-dlp init failed", t)
                ready.completeExceptionally(t)
                return@launch
            }
            ready.complete(Unit)
            updateIfDue(app)
        }
        startupUpdate = job
        job.start()
    }

    suspend fun <T> run(block: () -> T): T {
        ready.await()
        gate.enter()
        try {
            return withContext(Dispatchers.IO) { block() }
        } finally {
            gate.leave()
        }
    }

    suspend fun update(context: Context): YtDlpStatus {
        ready.await()
        gate.beginSwap()
        try {
            withContext(Dispatchers.IO) {
                YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
            }
        } finally {
            gate.endSwap()
        }
        NativePrefs.prefs(context).edit().putLong(KEY_CHECKED_AT, System.currentTimeMillis()).apply()
        // Not status(): the startup update runs this, and status() would wait on that job.
        return readStatus(context)
    }

    // Waits for init and a running startup update, so the Home chip never shows a version about to change.
    suspend fun status(context: Context): YtDlpStatus {
        ready.await()
        // A timeout stops the wait only, not the update, so a slow download never holds the chip.
        startupUpdate?.let { withTimeoutOrNull(STARTUP_WAIT_MS) { it.join() } }
        return readStatus(context)
    }

    fun setAutoUpdate(context: Context, enabled: Boolean) {
        NativePrefs.prefs(context).edit().putBoolean(KEY_AUTO_UPDATE, enabled).apply()
    }

    fun version(context: Context): String? = YoutubeDL.getInstance().version(context)

    private suspend fun readStatus(context: Context): YtDlpStatus = withContext(Dispatchers.IO) {
        val prefs = NativePrefs.prefs(context)
        YtDlpStatus(
            version = version(context),
            checkedAtMs = prefs.getLong(KEY_CHECKED_AT, 0L).takeIf { it > 0 },
            autoUpdate = prefs.getBoolean(KEY_AUTO_UPDATE, true),
        )
    }

    private suspend fun updateIfDue(context: Context) {
        val prefs = NativePrefs.prefs(context)
        val due = YtDlpSchedule.isDue(
            prefs.getLong(KEY_CHECKED_AT, 0L),
            System.currentTimeMillis(),
            prefs.getBoolean(KEY_AUTO_UPDATE, true),
        )
        if (!due) return
        try {
            update(context)
        } catch (e: Exception) {
            Log.w(TAG, "yt-dlp auto-update skipped", e)
        }
    }
}
