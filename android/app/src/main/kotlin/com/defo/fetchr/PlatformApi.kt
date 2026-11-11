package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.DownloadsSnapshot
import com.defo.fetchr.pigeon.DownloadsStreamHandler
import com.defo.fetchr.pigeon.FetchrError
import com.defo.fetchr.pigeon.FetchrHostApi
import com.defo.fetchr.pigeon.LibraryItem
import com.defo.fetchr.pigeon.PigeonEventSink
import com.defo.fetchr.pigeon.VideoInfo
import com.defo.fetchr.pigeon.YtDlpStatus
import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val SNAPSHOT_INTERVAL_MS = 250L

// The generated setUp would wrap a bare exception under its class name; Dart branches on these codes.
private inline fun <T> mapErrors(block: () -> T): T =
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (t: Throwable) {
        val (code, message) = ErrorClassifier.classify(t)
        throw FetchrError(code, message, null)
    }

class HostApi(private val activity: MainActivity) : FetchrHostApi {
    override suspend fun fetchInfo(url: String): VideoInfo = mapErrors {
        val safeUrl = RequestBuilder.requireHttpUrl(url)
        val request = RequestBuilder.info(safeUrl, activity.cacheDir)
        YtDlp.run { InfoParser.parse(YoutubeDL.getInstance().execute(request).out, safeUrl) }
    }

    override fun enqueue(requests: List<DownloadRequest>) = mapErrors {
        // Validate the whole batch first so a bad URL does not leave half of it queued.
        val checked = requests.map { it.copy(url = RequestBuilder.requireHttpUrl(it.url)) }
        FetchrApp.downloads.enqueue(checked)
    }

    override fun cancel(id: String) = mapErrors { FetchrApp.downloads.cancel(id) }

    override fun retry(id: String) = mapErrors { FetchrApp.downloads.retry(id) }

    override fun pause(id: String) = mapErrors { FetchrApp.downloads.pause(id) }

    override fun resume(id: String) = mapErrors { FetchrApp.downloads.resume(id) }

    override fun pauseAll() = mapErrors { FetchrApp.downloads.pauseAll() }

    override fun resumeAll() = mapErrors { FetchrApp.downloads.resumeAll() }

    override suspend fun awaitLaunchSplash() = mapErrors { activity.awaitLaunchSplash() }

    // The file goes first, so a declined dialog keeps the task, the only handle on the file.
    override suspend fun remove(id: String): Boolean = mapErrors {
        val uri = FetchrApp.downloads.savedUri(id)
        if (uri != null && !MediaLibrary.deleteFile(activity, uri)) {
            false
        } else {
            FetchrApp.downloads.remove(id)
            true
        }
    }

    override suspend fun listLibrary(folder: String): List<LibraryItem> = mapErrors {
        MediaLibrary.list(activity, folder)
    }

    override suspend fun deleteFromLibrary(uri: String): Boolean = mapErrors {
        MediaLibrary.deleteFile(activity, uri).also { deleted -> if (deleted) FetchrApp.downloads.forgetSaved(uri) }
    }

    override fun share(uri: String, mimeType: String) = mapErrors {
        MediaLibrary.share(activity, uri, mimeType)
    }

    override fun openFile(uri: String, mimeType: String) = mapErrors {
        MediaLibrary.open(activity, uri, mimeType)
    }

    override suspend fun openFolder(uri: String) = mapErrors { MediaLibrary.openFolder(activity, uri) }

    override suspend fun freeSpaceBytes(): Long = mapErrors { Storage.freeSpaceBytes() }

    override suspend fun pickVideo(): String? = mapErrors {
        val uri = activity.launchForResult(LocalVideo.pickerIntent())?.data ?: return@mapErrors null
        LocalVideo.keepAccess(activity.contentResolver, uri)
        uri.toString()
    }

    override suspend fun convertToMp3(uri: String, folder: String) = mapErrors {
        val request = withContext(Dispatchers.IO) { LocalVideo.request(activity.applicationContext, uri, folder) }
        FetchrApp.downloads.enqueue(listOf(request))
    }

    override suspend fun thumbnail(uri: String, widthPx: Long, heightPx: Long): String? = mapErrors {
        MediaLibrary.thumbnail(activity, uri, widthPx.toInt(), heightPx.toInt())
    }

    override suspend fun ytDlpStatus(): YtDlpStatus = mapErrors { YtDlp.status(activity.applicationContext) }

    override suspend fun updateYtDlp(): YtDlpStatus = mapErrors { YtDlp.update(activity.applicationContext) }

    override fun setYtDlpAutoUpdate(enabled: Boolean) = mapErrors {
        YtDlp.setAutoUpdate(activity.applicationContext, enabled)
    }

    override fun setAccentColor(argb: Long) = mapErrors { NativePrefs.setAccent(activity.applicationContext, argb) }
}

class DownloadsStream : DownloadsStreamHandler() {
    private var job: Job? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<DownloadsSnapshot>) {
        job?.cancel()
        // MainScope runs on the main thread, which is where the EventChannel sink must be called.
        job = MainScope().launch {
            FetchrApp.downloads.tasks.collect { tasks ->
                sink.success(DownloadsSnapshot(tasks))
                // tasks is a conflated StateFlow: progress ticks arriving during the delay collapse into one.
                delay(SNAPSHOT_INTERVAL_MS)
            }
        }
    }

    override fun onCancel(p0: Any?) {
        job?.cancel()
        job = null
    }
}
