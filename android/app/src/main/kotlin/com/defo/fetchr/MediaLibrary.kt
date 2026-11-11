package com.defo.fetchr

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Size
import android.webkit.MimeTypeMap
import com.defo.fetchr.pigeon.FetchrError
import com.defo.fetchr.pigeon.LibraryItem
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

object MediaLibrary {
    internal const val COPY_BUFFER_BYTES = 256 * 1024
    private const val EXTERNAL_STORAGE_AUTHORITY = "com.android.externalstorage.documents"
    private const val DECLINED = -1L
    private const val THUMB_DIR = "thumbs"
    private const val THUMB_QUALITY = 85
    // MediaStore has RELATIVE_PATH and scoped writes from API 29.
    private val scoped get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    private val PROJECTION_BASE = arrayOf(
        MediaStore.MediaColumns._ID,
        MediaStore.MediaColumns.DISPLAY_NAME,
        MediaStore.MediaColumns.MIME_TYPE,
        MediaStore.MediaColumns.SIZE,
        MediaStore.MediaColumns.DATE_ADDED,
    )

    suspend fun save(context: Context, file: File, kind: MediaKind, folder: String): String {
        val safe = RequestBuilder.safeFolder(folder)
        val mime = mimeFor(file, kind)
        return if (scoped) {
            saveScoped(context, file, kind, safe, mime)
        } else {
            saveLegacy(context, file, kind, safe, mime)
        }
    }

    // The path of a cached JPEG, so Flutter's image cache can hit on scroll-back; null when the item has no thumbnail.
    // ponytail: never evicted (a changed DATE_MODIFIED orphans its old file); the system clears cacheDir under pressure.
    suspend fun thumbnail(context: Context, uri: String, widthPx: Int, heightPx: Int): String? =
        withContext(Dispatchers.IO) {
            try {
                val target = Uri.parse(uri)
                val modified = context.contentResolver
                    .query(target, arrayOf(MediaStore.MediaColumns.DATE_MODIFIED), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) c.getLong(0) else null }
                    ?: return@withContext null
                val dir = File(context.cacheDir, THUMB_DIR).apply { mkdirs() }
                val cached = File(dir, "${sha256("$uri|$modified|${widthPx}x$heightPx")}.jpg")
                if (cached.exists()) return@withContext cached.path
                writeJpeg(decodeThumbnail(context, target, widthPx, heightPx), dir, cached)
            } catch (e: Exception) {
                null
            }
        }

    // loadThumbnail is API 29+; before that only video has MINI_KIND frames, and audio gets none.
    @Suppress("DEPRECATION")
    private fun decodeThumbnail(context: Context, uri: Uri, widthPx: Int, heightPx: Int): Bitmap? {
        val resolver = context.contentResolver
        if (scoped) return resolver.loadThumbnail(uri, Size(widthPx, heightPx), null)
        if (resolver.getType(uri)?.startsWith(MediaKind.VIDEO.mimePrefix) != true) return null
        return MediaStore.Video.Thumbnails.getThumbnail(
            resolver,
            ContentUris.parseId(uri),
            MediaStore.Video.Thumbnails.MINI_KIND,
            null,
        )
    }

    // A temp file renamed into place, so a second caller never reads a half-written JPEG.
    private fun writeJpeg(bitmap: Bitmap?, dir: File, target: File): String? {
        bitmap ?: return null
        val tmp = File.createTempFile("thumb", ".tmp", dir)
        try {
            val saved = tmp.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, THUMB_QUALITY, it) }
            return if (saved && tmp.renameTo(target)) target.path else null
        } finally {
            bitmap.recycle()
            tmp.delete()
        }
    }

    private fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    suspend fun list(context: Context, folder: String): List<LibraryItem> = withContext(Dispatchers.IO) {
        val safe = RequestBuilder.safeFolder(folder)
        (query(context, MediaKind.VIDEO, safe) + query(context, MediaKind.AUDIO, safe))
            .sortedByDescending { it.dateAddedMs }
    }

    // True when the file is gone, false when it is still there: the user declined the system dialog, or a file: uri could not be deleted.
    suspend fun deleteFile(activity: MainActivity, uri: String): Boolean {
        val target = Uri.parse(uri)
        // A failed scan on API 26 to 28 saves a file: uri, which has no MediaStore row and no dialog.
        if (target.scheme == "file") {
            val file = target.path?.let(::File) ?: return true
            return withContext(Dispatchers.IO) { !file.exists() || file.delete() }
        }
        if (target.authority != MediaStore.AUTHORITY) return true
        // The dialog's answer is the only truth after a consent request: an unowned row is invisible to exists().
        val rows = deleteOne(activity, target)
            ?: return activity.launchIntentSender(
                MediaStore.createDeleteRequest(activity.contentResolver, listOf(target)).intentSender,
            )
        if (rows == DECLINED) return false
        // No exception and no row matched: the row is already gone, or a race removed it.
        return rows > 0 || !exists(activity, target)
    }

    private suspend fun exists(context: Context, uri: Uri): Boolean = withContext(Dispatchers.IO) {
        context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
            ?.use { it.moveToFirst() } ?: false
    }

    // The rows deleted, DECLINED when the API 29 dialog was refused, or null when API 30+ needs the user's consent for a file the app does not own.
    private suspend fun deleteOne(activity: MainActivity, uri: Uri): Long? =
        try {
            deleteRows(activity, uri)
        } catch (e: SecurityException) {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> null
                Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException ->
                    if (activity.launchIntentSender(e.userAction.actionIntent.intentSender)) {
                        deleteRows(activity, uri)
                    } else {
                        DECLINED
                    }
                else -> throw e
            }
        }

    private suspend fun deleteRows(activity: MainActivity, uri: Uri): Long =
        withContext(Dispatchers.IO) { activity.contentResolver.delete(uri, null, null).toLong() }

    fun share(context: Context, uri: String, mimeType: String) = start(context, shareIntent(Uri.parse(uri), mimeType))

    fun open(context: Context, uri: String, mimeType: String) {
        start(context, viewIntent(Uri.parse(uri), mimeType))
    }

    // Throws no_folder_app when the item has no row or no app can show the folder. Android cannot highlight the file itself.
    suspend fun openFolder(activity: MainActivity, uri: String) {
        val id = withContext(Dispatchers.IO) { folderId(activity, Uri.parse(uri)) } ?: throw noFolderApp()
        // ponytail: primary volume only, which is all Fetchr saves to and lists; removable storage needs its volume id.
        val dir = DocumentsContract.buildDocumentUri(EXTERNAL_STORAGE_AUTHORITY, id)
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(dir, DocumentsContract.Document.MIME_TYPE_DIR)
        try {
            start(activity, view)
        } catch (e: ActivityNotFoundException) {
            throw noFolderApp()
        }
    }

    private fun noFolderApp() = FetchrError("no_folder_app", "No app can open this folder.", null)

    @Suppress("DEPRECATION")
    private fun folderId(context: Context, uri: Uri): String? {
        val root = Environment.getExternalStorageDirectory().path
        // A failed scan on API 26 to 28 saves a file: uri, whose path is the DATA value.
        if (uri.scheme == "file") return FolderPath.fromDataPath(uri.path, root)
        if (uri.authority != MediaStore.AUTHORITY) return null
        val column = if (scoped) MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
        val value = context.contentResolver.query(uri, arrayOf(column), null, null, null)
            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        return if (scoped) FolderPath.fromRelativePath(value) else FolderPath.fromDataPath(value, root)
    }

    fun viewIntent(uri: Uri, mime: String): Intent =
        Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

    // The system chooser for one file; the notifications' Share action uses it too.
    fun shareIntent(uri: Uri, mime: String): Intent =
        Intent.createChooser(
            Intent(Intent.ACTION_SEND)
                .setType(mime)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            null,
        )

    private suspend fun saveScoped(
        context: Context,
        file: File,
        kind: MediaKind,
        folder: String,
        mime: String,
    ): String = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${rootDir(kind)}/$folder")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection(kind), values)
            ?: throw IOException("MediaStore insert returned null")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IOException("Cannot open $uri for writing")
            out.use { sink -> file.inputStream().use { it.copyTo(sink, COPY_BUFFER_BYTES) } }
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        } catch (e: Throwable) {
            resolver.delete(uri, null, null)
            throw e
        }
        uri.toString()
    }

    private suspend fun saveLegacy(
        context: Context,
        file: File,
        kind: MediaKind,
        folder: String,
        mime: String,
    ): String {
        val target = withContext(Dispatchers.IO) {
            val dir = legacyDir(kind, folder)
            if (!(dir.mkdirs() || dir.isDirectory)) {
                val denied = context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                    PackageManager.PERMISSION_GRANTED
                // Coded here, so the user is sent to the app settings whatever the message says.
                if (denied) throw FetchrError("permission_denied", ErrorClassifier.PERMISSION_DENIED_MESSAGE, null)
                throw IOException("Cannot create ${dir.path}")
            }
            val out = uniqueFile(dir, file.name)
            try {
                file.copyTo(out, bufferSize = COPY_BUFFER_BYTES)
            } catch (e: Throwable) {
                out.delete()
                throw e
            }
            out
        }
        return scan(context, target, mime)
    }

    private suspend fun scan(context: Context, file: File, mime: String): String =
        suspendCancellableCoroutine { cont ->
            MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf(mime)) { _, uri ->
                // A failed scan leaves no MediaStore row; the file URI still plays in-app.
                cont.resume((uri ?: Uri.fromFile(file)).toString())
            }
        }

    @Suppress("DEPRECATION")
    private fun query(context: Context, kind: MediaKind, folder: String): List<LibraryItem> {
        val audio = kind == MediaKind.AUDIO
        val duration = if (audio) MediaStore.Audio.Media.DURATION else MediaStore.Video.Media.DURATION
        val base = collection(kind)
        // Audio has no dimensions to ask for.
        val dimensions = if (audio) {
            emptyArray<String>()
        } else {
            arrayOf(MediaStore.MediaColumns.WIDTH, MediaStore.MediaColumns.HEIGHT)
        }
        // The scoped selection pins RELATIVE_PATH, so every row has this value and the column is never read.
        val pinned = "${rootDir(kind)}/$folder/"
        val (selection, args) = if (scoped) {
            // MediaProvider stores RELATIVE_PATH with a trailing slash.
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?" to arrayOf(pinned)
        } else {
            val prefix = legacyDir(kind, folder).path
                .replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            "${MediaStore.MediaColumns.DATA} LIKE ? ESCAPE '\\'" to arrayOf("$prefix/%")
        }
        // Before API 29 the folder is only in DATA, the file's absolute path.
        val legacyPath = if (scoped) emptyArray<String>() else arrayOf(MediaStore.MediaColumns.DATA)
        val cursor = context.contentResolver.query(
            base,
            PROJECTION_BASE + duration + legacyPath + dimensions,
            selection,
            args,
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        ) ?: return emptyList()
        return cursor.use { c ->
            val id = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val name = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val mime = c.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val size = c.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val added = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_ADDED)
            val dur = c.getColumnIndexOrThrow(duration)
            // -1 for a column the query did not ask for.
            val data = c.getColumnIndex(MediaStore.MediaColumns.DATA)
            val width = c.getColumnIndex(MediaStore.MediaColumns.WIDTH)
            val height = c.getColumnIndex(MediaStore.MediaColumns.HEIGHT)
            buildList {
                while (c.moveToNext()) {
                    add(
                        LibraryItem(
                            uri = ContentUris.withAppendedId(base, c.getLong(id)).toString(),
                            name = c.getString(name) ?: "",
                            mimeType = c.getString(mime) ?: kind.defaultMime,
                            isAudio = audio,
                            sizeBytes = c.getLong(size),
                            durationMs = if (c.isNull(dur)) null else c.getLong(dur),
                            dateAddedMs = c.getLong(added) * 1000,
                            width = c.positiveLong(width),
                            height = c.positiveLong(height),
                            relativePath = if (scoped) pinned else legacyRelativePath(c.getString(data)),
                        ),
                    )
                }
            }
        }
    }

    // MediaStore stores 0 for dimensions it could not read; index -1 is a column the query did not ask for.
    private fun Cursor.positiveLong(index: Int): Long? =
        if (index < 0 || isNull(index)) null else getLong(index).takeIf { it > 0 }

    private fun legacyRelativePath(data: String?): String? =
        FolderPath.relativeOfData(data, Environment.getExternalStorageDirectory().path)

    private fun collection(kind: MediaKind): Uri =
        when (kind) {
            MediaKind.VIDEO ->
                if (scoped) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            MediaKind.AUDIO ->
                if (scoped) MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            MediaKind.IMAGE ->
                if (scoped) MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

    private fun rootDir(kind: MediaKind): String =
        when (kind) {
            MediaKind.VIDEO -> Environment.DIRECTORY_MOVIES
            MediaKind.AUDIO -> Environment.DIRECTORY_MUSIC
            MediaKind.IMAGE -> Environment.DIRECTORY_PICTURES
        }

    @Suppress("DEPRECATION")
    private fun legacyDir(kind: MediaKind, folder: String): File =
        File(Environment.getExternalStoragePublicDirectory(rootDir(kind)), folder)

    private fun mimeFor(file: File, kind: MediaKind): String {
        val guess = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())
        return guess?.takeIf { it.startsWith(kind.mimePrefix) } ?: kind.defaultMime
    }

    private fun uniqueFile(dir: File, name: String): File {
        val first = File(dir, name)
        if (!first.exists()) return first
        val stem = first.nameWithoutExtension
        val ext = first.extension.let { if (it.isEmpty()) "" else ".$it" }
        return generateSequence(1) { it + 1 }
            .map { File(dir, "$stem ($it)$ext") }
            .first { !it.exists() }
    }

    private fun start(context: Context, intent: Intent) {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
