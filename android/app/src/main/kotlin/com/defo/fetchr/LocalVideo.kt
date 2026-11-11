package com.defo.fetchr

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.FetchrError
import com.defo.fetchr.pigeon.Quality
import java.io.File
import java.io.IOException

// A video on the device turned into an MP3 by the download pipeline. Its task's url is the content: or file: uri;
// each attempt copies the video into the task dir under the name yt-dlp would save it as, so yt-dlp finds it
// "already downloaded" and only converts it (and deletes the copy).
internal object LocalVideo {
    private const val PICK_IMAGES = "android.provider.action.PICK_IMAGES"
    private const val DEFAULT_NAME = "video"
    private const val DEFAULT_EXTENSION = "mp4"

    fun isLocal(url: String): Boolean = url.startsWith("content:") || url.startsWith("file:")

    // The photo picker needs no permission; it reached API 30 to 32 through a system update. Elsewhere the Files
    // app's picker.
    fun pickerIntent(): Intent {
        val photoPicker = Build.VERSION.SDK_INT >= 33 ||
            (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)
        return if (photoPicker) {
            Intent(PICK_IMAGES).setType("video/*")
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("video/*")
        }
    }

    // A picker's grant ends with the process; a persisted one lets a retry after a restart read the video again.
    fun keepAccess(resolver: ContentResolver, uri: Uri) {
        try {
            resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (e: SecurityException) {
            // Not persistable (a library item, an older picker): readable for this run only.
        }
    }

    // Blocking: reads the name and the duration, which ffmpeg's report is measured against.
    fun request(context: Context, uri: String, folder: String): DownloadRequest {
        if (!isLocal(uri)) throw FetchrError("invalid_url", "Not a video on this device", null)
        val parsed = Uri.parse(uri)
        return DownloadRequest(
            url = uri,
            title = displayName(context, parsed)?.substringBeforeLast('.')?.takeIf { it.isNotBlank() } ?: DEFAULT_NAME,
            quality = Quality.MP3,
            folder = folder,
            useAria2c = false,
            durationSeconds = durationSeconds(context, parsed),
        )
    }

    // The copy yt-dlp converts. A copy left whole by an earlier attempt is reused.
    fun stage(context: Context, req: DownloadRequest, dir: File): File {
        val uri = Uri.parse(req.url)
        val target = File(dir, "${RequestBuilder.safeFileName(req.title)}.${extension(context, uri)}")
        if (target.isFile) return target
        val partial = File(dir, "${target.name}.copying")
        try {
            val input = context.contentResolver.openInputStream(uri) ?: throw IOException("No stream for the video")
            input.use { src -> partial.outputStream().use { src.copyTo(it, MediaLibrary.COPY_BUFFER_BYTES) } }
        } catch (e: SecurityException) {
            throw FetchrError("unavailable", "The video can no longer be read", null)
        } catch (e: java.io.FileNotFoundException) {
            throw FetchrError("unavailable", "The video is gone", null)
        }
        if (!partial.renameTo(target)) throw IOException("Could not stage the video")
        return target
    }

    private fun displayName(context: Context, uri: Uri): String? {
        if (uri.scheme == ContentResolver.SCHEME_FILE) return uri.lastPathSegment
        return try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (e: RuntimeException) {
            null
        }
    }

    private fun durationSeconds(context: Context, uri: Uri): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                ?.div(1000)?.takeIf { it > 0 }
        } catch (e: RuntimeException) {
            null
        } finally {
            // Declared to throw IOException since API 29.
            runCatching { retriever.release() }
        }
    }

    // The file's own extension, which is also what yt-dlp names its output after.
    private fun extension(context: Context, uri: Uri): String {
        val fromName = displayName(context, uri)?.substringAfterLast('.', "")
            ?.takeIf { it.isNotEmpty() && it.all(Char::isLetterOrDigit) }
        return fromName?.lowercase()
            ?: context.contentResolver.getType(uri)?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
            ?: DEFAULT_EXTENSION
    }
}
