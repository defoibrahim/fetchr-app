package com.defo.fetchr

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import com.yausername.youtubedl_android.YoutubeDL
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

class DownloadRepository(context: Context) {
    private companion object {
        const val TAG = "DownloadRepository"
        const val MAX_PARALLEL = 2
        const val TEMP_DIR = "downloads"
        const val STALL_CHECK_MS = 5_000L
        const val STALL_AFTER_MS = 30_000L

        // ffmpeg appends a block to its -progress report every half second.
        const val CONVERSION_POLL_MS = 500L
    }


    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val permits = Semaphore(MAX_PARALLEL)
    private val jobs = ConcurrentHashMap<String, Job>()

    // Orders status changes against job hand-over, so a retried task is never overwritten by the attempt it replaces.
    private val lock = Any()
    private val persistLock = Any()
    private val store = AtomicFile(File(appContext.filesDir, "downloads.json"))
    private val state = MutableStateFlow(load())

    val tasks: StateFlow<List<DownloadTask>> = state.asStateFlow()
    val hasActive: Boolean get() = state.value.any { it.isLive }

    // A dead process leaves dirs behind; only those no paused or failed task resumes from are deleted, and so are the
    // aria2c cookie files a killed run left in cache/. This runs in Application.onCreate, so it stays off the main
    // thread; runTask joins it before making a temp dir.
    private val tempCleanup = state.value.let { loaded ->
        // Read before the launch, so a cookie file a run of this process creates is never taken for a stale one.
        val startedAtMs = System.currentTimeMillis()
        scope.launch {
            val root = File(appContext.cacheDir, TEMP_DIR)
            TempDirs.orphans(root.list().orEmpty().toList(), loaded).forEach { File(root, it).deleteRecursively() }
            TempDirs.deleteStaleCookieFiles(appContext.cacheDir, startedAtMs)
        }
    }

    fun enqueue(requests: List<DownloadRequest>) {
        if (requests.isEmpty()) return
        val now = System.currentTimeMillis()
        val added = requests.map {
            DownloadTask(
                id = UUID.randomUUID().toString(),
                request = it,
                status = TaskStatus.QUEUED,
                progress = 0.0,
                etaSeconds = -1L,
                createdAtMs = now,
                stage = TaskStage.PREPARING,
                stalled = false,
            )
        }
        state.update { added + it }
        persistAsync()
        startService()
        added.forEach { launchRun(it.id) }
    }

    fun cancel(id: String) {
        settle(id) { TaskTransitions.cancel(it, System.currentTimeMillis()) } ?: return
        stop(id, discardFiles = true)
    }

    fun cancelAll() {
        state.value.filter { it.isLive }.forEach { cancel(it.id) }
    }

    fun pause(id: String) {
        settle(id, rule = TaskTransitions::pause) ?: return
        stop(id, discardFiles = false)
    }

    fun pauseAll() {
        state.value.filter { it.isLive }.forEach { pause(it.id) }
    }

    fun resume(id: String) = relaunch(id, TaskTransitions::resume)

    fun resumeAll() {
        state.value.filter { it.status == TaskStatus.PAUSED }.forEach { resume(it.id) }
    }

    fun retry(id: String) = relaunch(id, TaskTransitions::retry)

    // Only a completed task owns a saved file; a retried one has cleared its uri.
    fun savedUri(id: String): String? =
        state.value.firstOrNull { it.id == id && it.status == TaskStatus.COMPLETED }?.savedUri

    fun remove(id: String) {
        synchronized(lock) { state.update { list -> list.filterNot { it.id == id } } }
        stop(id, discardFiles = true)
        persistAsync()
    }

    // A file deleted from the Library takes its finished task along: the row could only open a file that is gone.
    fun forgetSaved(uri: String) {
        state.value.filter { it.status == TaskStatus.COMPLETED && it.savedUri == uri }.forEach { remove(it.id) }
    }

    private fun relaunch(id: String, op: (DownloadTask) -> DownloadTask?) {
        synchronized(lock) { settle(id, rule = op)?.also { launchRun(id) } } ?: return
        // A Retry from the app as well as from the notification: the failure it reported is over.
        DownloadNotifications.dismissResult(appContext, id)
        startService()
    }

    private fun launchRun(id: String) = chain(id) { runTask(id) }

    // Work on a task queues behind the attempt it replaces, which may still be unwinding in the same temp dir.
    private fun chain(id: String, block: suspend () -> Unit) {
        val previous = jobs[id]
        val job = scope.launch(start = CoroutineStart.LAZY) {
            previous?.join()
            block()
        }
        jobs[id] = job
        job.invokeOnCompletion { jobs.remove(id, job) }
        job.start()
    }

    private fun dirOf(id: String) = File(appContext.cacheDir, "$TEMP_DIR/$id")

    private fun statusOf(id: String): TaskStatus? = state.value.firstOrNull { it.id == id }?.status

    private suspend fun runTask(id: String) {
        tempCleanup.join()
        val self = currentCoroutineContext()[Job]
        val dir = dirOf(id)
        try {
            permits.withPermit {
                // Not persisted: a restart loads queued and running tasks alike as interrupted.
                val running = transition(id, self, TaskTransitions::start) ?: return
                val file = download(id, running.request, dir, self)
                // The file is whole: a pause or resume landing now must not leave it unsaved in the temp dir, or
                // the next attempt would find it, save it again and add a second copy to the library.
                withContext(NonCancellable) { complete(id, running.request, file) }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: YoutubeDL.CanceledException) {
            // cancel(), pause() and remove() have already recorded the outcome. A late destroyProcessById aimed at
            // the attempt before this one leaves the task running with no process, so fail it for a Retry.
            settle(id, self) {
                if (it.status == TaskStatus.RUNNING) TaskTransitions.interrupted(it, System.currentTimeMillis()) else null
            }
        } catch (t: Throwable) {
            val (code, message) = ErrorClassifier.classify(t)
            Log.w(TAG, "Task $id failed: $code")
            settle(id, self) { if (it.isLive) TaskTransitions.fail(it, code, message, System.currentTimeMillis()) else null }
        } finally {
            if (!keepsDir(statusOf(id))) dir.deleteRecursively()
        }
    }

    // A task queued again (resumed while this attempt was still unwinding) goes on from these files.
    private fun keepsDir(status: TaskStatus?): Boolean =
        status != null && (TaskTransitions.keepsPartialFiles(status) || status == TaskStatus.QUEUED)

    private suspend fun complete(id: String, req: DownloadRequest, file: File) {
        val bytes = file.length()
        val uri = MediaLibrary.save(appContext, file, req.quality.mediaKind, req.folder)
        settle(id) { TaskTransitions.complete(it, uri, bytes, System.currentTimeMillis()) }
    }

    private suspend fun download(id: String, req: DownloadRequest, dir: File, self: Job?): File {
        // Not wiped: yt-dlp continues the .part files an earlier attempt left here.
        dir.mkdirs()
        val request = if (LocalVideo.isLocal(req.url)) {
            RequestBuilder.convert(LocalVideo.stage(appContext, req, dir), appContext.cacheDir)
        } else {
            RequestBuilder.download(req, dir, appContext.cacheDir, appContext.noBackupFilesDir)
        }
        val ctx = currentCoroutineContext()
        YtDlp.run {
            val lastLineAt = AtomicLong(System.currentTimeMillis())
            val watchdog = scope.launch { watchStall(id, self, lastLineAt) }
            val conversion = req.durationSeconds?.takeIf { req.quality == Quality.MP3 && it > 0 }?.let { seconds ->
                scope.launch { watchConversion(id, self, File(dir, RequestBuilder.CONVERSION_REPORT), seconds) }
            }
            try {
                YoutubeDL.getInstance().execute(request, id) { percent, eta, line ->
                    // Covers a cancel that landed before the process was registered for destroyProcessById.
                    if (!ctx.isActive) YoutubeDL.getInstance().destroyProcessById(id)
                    if (onLine(id, self, percent, eta, ProgressLine.parse(line))) {
                        lastLineAt.set(System.currentTimeMillis())
                    }
                }
            } finally {
                watchdog.cancel()
                conversion?.cancel()
            }
        }
        ctx.ensureActive()
        // An MP3 is the .mp3 alone: a local video's copy outweighs it if yt-dlp ever leaves it behind.
        return dir.listFiles().orEmpty()
            .filter { it.isFile && !it.name.endsWith(".part") }
            .filter { req.quality != Quality.MP3 || it.extension.equals("mp3", ignoreCase = true) }
            .maxByOrNull { it.length() }
            ?: throw IOException("yt-dlp finished without producing a file")
    }

    // True when the line shows the download alive, which resets the stall watchdog.
    private fun onLine(id: String, owner: Job?, libraryPercent: Float, libraryEta: Long, stats: ProgressStats?): Boolean {
        // Read without the lock: most lines move nothing.
        val current = state.value.firstOrNull { it.id == id }?.takeIf { it.status == TaskStatus.RUNNING } ?: return false
        val (next, alive) = current.onLine(libraryPercent, libraryEta, stats)
        if (progressChanged(current, next)) {
            transition(id, owner) {
                if (it.status == TaskStatus.RUNNING) it.onLine(libraryPercent, libraryEta, stats).first else null
            }
        }
        return alive
    }

    private suspend fun watchStall(id: String, owner: Job?, lastLineAt: AtomicLong) {
        while (true) {
            delay(STALL_CHECK_MS)
            val silent = System.currentTimeMillis() - lastLineAt.get() >= STALL_AFTER_MS
            transition(id, owner) {
                // ffmpeg prints nothing while it merges, so silence there is not a stall.
                val stalled = silent && it.stage != TaskStage.POST_PROCESSING
                if (it.status != TaskStatus.RUNNING || stalled == it.stalled) null else it.copy(stalled = stalled)
            }
        }
    }

    // yt-dlp prints nothing while ffmpeg converts; ffmpeg's report says how far it has got.
    private suspend fun watchConversion(id: String, owner: Job?, report: File, durationSeconds: Long) {
        while (true) {
            delay(CONVERSION_POLL_MS)
            val converting = state.value.any { it.id == id && it.stage == TaskStage.POST_PROCESSING }
            if (!converting || !report.isFile) continue
            val progress = try {
                ProgressLine.conversion(report.readText(), durationSeconds)
            } catch (e: IOException) {
                null
            } ?: continue
            transition(id, owner) { it.withConversion(progress) }
        }
    }

    private fun stop(id: String, discardFiles: Boolean) {
        jobs[id]?.cancel()
        // destroyProcessById forks a shell to kill the process tree; callers sit on the main thread.
        scope.launch {
            try {
                YoutubeDL.getInstance().destroyProcessById(id)
            } catch (e: RuntimeException) {
                Log.w(TAG, "Could not stop the process of $id", e)
            }
        }
        if (discardFiles) chain(id) { dirOf(id).deleteRecursively() }
    }

    // A rule returns null when it does not apply to the task as it now is.
    private fun settle(id: String, owner: Job? = null, rule: (DownloadTask) -> DownloadTask?): DownloadTask? {
        val task = transition(id, owner, rule) ?: return null
        persistAsync()
        try {
            DownloadNotifications.finished(appContext, task)
        } catch (e: RuntimeException) {
            Log.w(TAG, "Could not post the result notification", e)
        }
        return task
    }

    private fun transition(id: String, owner: Job? = null, rule: (DownloadTask) -> DownloadTask?): DownloadTask? =
        synchronized(lock) {
            if (owner != null && jobs[id] !== owner) return@synchronized null
            var changed: DownloadTask? = null
            state.update { list ->
                changed = null
                list.map { t -> if (t.id == id) rule(t)?.also { changed = it } ?: t else t }
            }
            changed
        }

    private fun startService() {
        try {
            DownloadService.start(appContext)
        } catch (e: RuntimeException) {
            // Downloads still run while the process lives; only the foreground notification is lost.
            Log.w(TAG, "Could not start DownloadService", e)
        }
    }

    private fun load(): List<DownloadTask> =
        runCatching { TaskCodec.decode(String(store.readFully(), Charsets.UTF_8)) }
            .getOrDefault(emptyList())
            .sortedByDescending { it.createdAtMs }

    private fun persistAsync() {
        scope.launch { persist() }
    }

    private fun persist() {
        synchronized(persistLock) {
            val out = try {
                store.startWrite()
            } catch (e: IOException) {
                Log.w(TAG, "Could not save the download list", e)
                return
            }
            try {
                out.write(TaskCodec.encode(state.value).toByteArray(Charsets.UTF_8))
                store.finishWrite(out)
            } catch (e: IOException) {
                store.failWrite(out)
                Log.w(TAG, "Could not save the download list", e)
            }
        }
    }
}

val DownloadTask.isLive: Boolean
    get() = status == TaskStatus.QUEUED || status == TaskStatus.RUNNING

private const val PROGRESS_STEP = 0.005

// Ticks that barely move the bar only churn every collector of the task list. Entering or leaving
// the unknown state (-1) always passes, and so does a new ETA, stage or stall reading.
internal fun progressChanged(last: DownloadTask, next: DownloadTask): Boolean =
    next.etaSeconds != last.etaSeconds ||
        next.stage != last.stage ||
        next.stalled != last.stalled ||
        (next.progress < 0) != (last.progress < 0) ||
        abs(next.progress - last.progress) >= PROGRESS_STEP
