package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.FetchrError
import com.defo.fetchr.pigeon.Quality
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File
import java.net.URL

object RequestBuilder {
    private const val DEFAULT_FOLDER = "Fetchr"
    private const val DEFAULT_NAME = "video"

    // Bytes are what file systems cap; 150 characters stays under 255 bytes for most scripts.
    private const val MAX_NAME = 150
    private const val OUTPUT_TEMPLATE = "%(title).150B [%(id)s].%(ext)s"

    // ffmpeg's -progress report while an MP3 converts, in the task dir. yt-dlp keeps ffmpeg's own output to itself.
    const val CONVERSION_REPORT = "ffmpeg.progress"
    private val FOLDER_FORBIDDEN = setOf('\\', '/', ':', '*', '?', '"', '<', '>', '|')

    // Parallel HLS/DASH fragments per task. Two tasks run at once, so 4 means at most 8 requests to a server; a
    // benchmark showed no gain past about 10. Single files and covers ignore it, and aria2c cannot take fragments.
    private const val CONCURRENT_FRAGMENTS = "4"
    private val YOUTUBE_DOMAINS = listOf("youtube.com", "youtu.be", "youtube-nocookie.com")

    fun requireHttpUrl(url: String): String = url.trim().also { parseHttpUrl(it) }

    // The scheme check also keeps a value starting with "-" from ever reaching yt-dlp as an option. java.net.URL, not
    // URI: URI rejects characters such as "|" that a link can carry and yt-dlp takes.
    private fun parseHttpUrl(trimmed: String): URL {
        val parsed = runCatching { URL(trimmed) }.getOrNull()
        if (parsed == null ||
            (parsed.protocol != "http" && parsed.protocol != "https") ||
            parsed.host.isEmpty() ||
            trimmed.any { it.isWhitespace() || it.isISOControl() }
        ) {
            throw FetchrError("invalid_url", "That is not a valid web link.", null)
        }
        return parsed
    }

    fun safeFolder(name: String): String =
        name.filterNot { it in FOLDER_FORBIDDEN || it.isISOControl() }
            .trimStart { it == '.' || it.isWhitespace() }
            .trimEnd()
            .ifEmpty { DEFAULT_FOLDER }

    // A file name for yt-dlp's -o, where % starts a template field.
    fun safeFileName(name: String): String =
        name.filterNot { it in FOLDER_FORBIDDEN || it == '%' || it.isISOControl() }
            .trimStart { it == '.' || it == '-' || it.isWhitespace() }
            .trimEnd()
            .take(MAX_NAME)
            .ifEmpty { DEFAULT_NAME }

    // [source] is a video LocalVideo copied into the task dir. yt-dlp finds it already where -o points, so it only
    // converts it. File URLs are switched on for this request only, and the uri never comes from outside.
    fun convert(source: File, cacheDir: File): YoutubeDLRequest {
        val outDir = source.absoluteFile.parentFile!!
        return YoutubeDLRequest("file://" + source.absoluteFile.toURI().rawPath)
            .addOption("--enable-file-urls")
            .addOption("--no-mtime")
            .addOption("--cache-dir", ytDlpCache(cacheDir))
            .addOption("-o", File(outDir, "${source.nameWithoutExtension}.%(ext)s").path)
            .mp3(outDir)
    }

    private fun YoutubeDLRequest.mp3(outDir: File): YoutubeDLRequest =
        addOption("-f", "ba/b")
            .addOption("-x")
            .addOption("--audio-format", "mp3")
            .addOption("--audio-quality", "0")
            // yt-dlp splits this like a shell; -progress is global, so ffmpeg takes it among the output options.
            .addOption("--postprocessor-args", "ExtractAudio+ffmpeg:-progress \"${File(outDir, CONVERSION_REPORT).path}\"")

    fun info(url: String, cacheDir: File): YoutubeDLRequest =
        YoutubeDLRequest(requireHttpUrl(url))
            .addOption("-J")
            .addOption("--flat-playlist")
            .addOption("--cache-dir", ytDlpCache(cacheDir))

    fun download(req: DownloadRequest, outDir: File, cacheDir: File, noBackupDir: File): YoutubeDLRequest {
        val url = req.url.trim()
        val host = parseHttpUrl(url).host
        val request = YoutubeDLRequest(url)
            .addOption("--no-playlist")
            .addOption("--no-mtime")
            .addOption("--cache-dir", ytDlpCache(cacheDir))
            .addOption("-o", File(outDir, OUTPUT_TEMPLATE).path)
            .addOption("-N", CONCURRENT_FRAGMENTS)
        when (req.quality) {
            Quality.MP3 -> request.mp3(outDir)
            // The converted .jpg is the only file left in the task dir.
            Quality.COVER -> request.addOption("--skip-download")
                .addOption("--write-thumbnail")
                .addOption("--convert-thumbnails", "jpg")
            Quality.BEST, Quality.P1080, Quality.P720, Quality.P480 ->
                request.addOption("-f", "bv*+ba/b")
                    .addOption("-S", videoSort(req.quality))
                    .addOption("--merge-output-format", "mp4")
        }
        if (req.useAria2c && !isYouTubeHost(host)) {
            request.addOption("--downloader", "libaria2c.so")
            // The library sends two aria2c args (interval, then CA cert) and yt-dlp keeps only the last, so the
            // interval is lost. addCommands lands after all library options: this one value carries both and wins.
            request.addCommands(
                listOf("--downloader-args", "aria2c:--summary-interval=1 --ca-certificate=${caCert(noBackupDir).path}"),
            )
        }
        return request
    }

    // yt-dlp's maintainers strongly discourage aria2c with YouTube, which throttles requests over 10 MB; the native
    // downloader keeps to 10 MiB chunks. The parsed host is matched, never a substring.
    private fun isYouTubeHost(host: String): Boolean {
        val name = host.lowercase().trimEnd('.')
        return YOUTUBE_DOMAINS.any { name == it || name.endsWith(".$it") }
    }

    private fun ytDlpCache(cacheDir: File): String = File(cacheDir, "yt-dlp").path

    // Where youtubedl-android puts the cert it hands to yt-dlp as SSL_CERT_FILE, relative to noBackupFilesDir.
    private fun caCert(noBackupDir: File): File =
        File(noBackupDir, "youtubedl-android/packages/python/usr/etc/tls/cert.pem")

    // yt-dlp's res is the smaller of width and height, so a cap holds for portrait video too.
    private fun videoSort(quality: Quality): String {
        val res = quality.shortSideCap?.let { "res:$it" } ?: "res"
        return "$res,vcodec:h264,acodec:aac"
    }
}

// The cap on a video's shorter side that a quality asks for; null when it has none.
internal val Quality.shortSideCap: Int?
    get() = when (this) {
        Quality.P1080 -> 1080
        Quality.P720 -> 720
        Quality.P480 -> 480
        Quality.BEST, Quality.MP3, Quality.COVER -> null
    }
