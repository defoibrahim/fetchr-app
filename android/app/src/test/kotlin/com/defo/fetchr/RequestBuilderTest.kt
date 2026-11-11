package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.FetchrError
import com.defo.fetchr.pigeon.Quality
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RequestBuilderTest {
    private val url = "https://example.com/watch?v=abc&list=xyz"
    private val cacheDir = File("cache")
    private val outDir = File("out")
    private val noBackupDir = File("nobackup")

    private val ytDlpCache = File(cacheDir, "yt-dlp").path
    private val caCert = File(noBackupDir, "youtubedl-android/packages/python/usr/etc/tls/cert.pem").path
    private val aria2cArgs = listOf(
        "--downloader-args", "aria2c:--summary-interval=1 --ca-certificate=$caCert",
    )
    private val template = File(outDir, "%(title).150B [%(id)s].%(ext)s").path
    private val common = listOf(
        "--no-playlist", "--no-mtime", "--cache-dir", ytDlpCache, "-o", template, "-N", "4",
    )
    private val videoFormat = listOf("-f", "bv*+ba/b")
    private val mergeTail = listOf("--merge-output-format", "mp4")

    private fun sort(res: String) = listOf("-S", "$res,vcodec:h264,acodec:aac")

    private fun request(quality: Quality, useAria2c: Boolean = false, link: String = url) =
        DownloadRequest(
            url = link,
            title = "A title",
            thumbnail = null,
            quality = quality,
            folder = "Fetchr",
            useAria2c = useAria2c,
        )

    private fun command(quality: Quality, useAria2c: Boolean = false, link: String = url) =
        RequestBuilder.download(request(quality, useAria2c, link), outDir, cacheDir, noBackupDir).buildCommand()

    private fun assertInvalidUrl(block: () -> Unit) {
        try {
            block()
        } catch (e: FetchrError) {
            assertEquals("invalid_url", e.code)
            return
        }
        fail("expected FetchrError(invalid_url)")
    }

    @Test
    fun requireHttpUrl_acceptsHttpAndHttps() {
        assertEquals("http://example.com/a", RequestBuilder.requireHttpUrl("http://example.com/a"))
        assertEquals(url, RequestBuilder.requireHttpUrl(url))
        assertEquals("HTTPS://Example.com/a", RequestBuilder.requireHttpUrl("HTTPS://Example.com/a"))
        assertEquals("https://[::1]:8080/a", RequestBuilder.requireHttpUrl("https://[::1]:8080/a"))
    }

    @Test
    fun requireHttpUrl_trimsSurroundingWhitespace() {
        assertEquals(url, RequestBuilder.requireHttpUrl("  $url\n"))
    }

    @Test
    fun requireHttpUrl_rejectsEverythingElse() {
        val bad = listOf(
            "",
            "   ",
            "example.com/watch?v=1",
            "ftp://example.com/a",
            "file:///etc/passwd",
            "content://media/external/video/1",
            "javascript:alert(1)",
            "https://",
            "http:///no-host",
            "http:example.com",
            "--exec https://example.com",
            "-J",
            "https://exa mple.com",
            "https://example.com/a\nb",
            "https://example.com/a\u0000b",
        )
        for (candidate in bad) {
            assertInvalidUrl { RequestBuilder.requireHttpUrl(candidate) }
        }
    }

    @Test
    fun safeFolder_keepsPlainNames() {
        assertEquals("Fetchr", RequestBuilder.safeFolder("Fetchr"))
        assertEquals("My Videos", RequestBuilder.safeFolder("My Videos"))
        assertEquals("a.b", RequestBuilder.safeFolder("a.b"))
    }

    @Test
    fun safeFolder_stripsReservedCharacters() {
        assertEquals("abcdefghij", RequestBuilder.safeFolder("a\\b/c:d*e?f\"g<h>i|j"))
        assertEquals("ab", RequestBuilder.safeFolder("a\u0000\nb"))
    }

    @Test
    fun safeFolder_stripsLeadingDots() {
        assertEquals("hidden", RequestBuilder.safeFolder("..hidden"))
        assertEquals("etc", RequestBuilder.safeFolder("../../etc"))
        assertEquals("x", RequestBuilder.safeFolder(". . x"))
    }

    @Test
    fun safeFolder_trimsWhitespace() {
        assertEquals("Clips", RequestBuilder.safeFolder("  Clips "))
    }

    @Test
    fun safeFolder_blankFallsBackToFetchr() {
        for (blank in listOf("", "   ", ".", "...", "///", ".\\.", "*?", "\t")) {
            assertEquals("for '$blank'", "Fetchr", RequestBuilder.safeFolder(blank))
        }
    }

    @Test
    fun info_buildsFlatJsonDump() {
        val cmd = RequestBuilder.info(url, cacheDir).buildCommand()
        assertEquals(listOf("-J", "--flat-playlist", "--cache-dir", ytDlpCache, url), cmd)
    }

    @Test
    fun info_trimsUrl() {
        val cmd = RequestBuilder.info("  $url ", cacheDir).buildCommand()
        assertEquals(url, cmd.last())
    }

    @Test
    fun info_rejectsNonHttpUrl() {
        assertInvalidUrl { RequestBuilder.info("file:///etc/passwd", cacheDir) }
    }

    @Test
    fun download_best() {
        assertEquals(
            common + videoFormat + sort("res") + mergeTail + url,
            command(Quality.BEST),
        )
    }

    @Test
    fun download_p1080() {
        assertEquals(
            common + videoFormat + sort("res:1080") + mergeTail + url,
            command(Quality.P1080),
        )
    }

    @Test
    fun download_p720() {
        assertEquals(
            common + videoFormat + sort("res:720") + mergeTail + url,
            command(Quality.P720),
        )
    }

    @Test
    fun download_p480() {
        assertEquals(
            common + videoFormat + sort("res:480") + mergeTail + url,
            command(Quality.P480),
        )
    }

    @Test
    fun download_capsTheShortSideNotTheHeight() {
        for (quality in listOf(Quality.P1080, Quality.P720, Quality.P480)) {
            val cmd = command(quality)
            assertTrue(cmd.none { it.contains("height") })
            assertEquals(videoFormat, cmd.subList(cmd.indexOf("-f"), cmd.indexOf("-f") + 2))
        }
    }

    @Test
    fun shortSideCap_isTheOnlyCapTable() {
        assertEquals(1080, Quality.P1080.shortSideCap)
        assertEquals(720, Quality.P720.shortSideCap)
        assertEquals(480, Quality.P480.shortSideCap)
        assertNull(Quality.BEST.shortSideCap)
        assertNull(Quality.MP3.shortSideCap)
        assertNull(Quality.COVER.shortSideCap)
    }

    @Test
    fun download_mp3() {
        val cmd = command(Quality.MP3)
        assertEquals(
            common + listOf("-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0") +
                listOf("--postprocessor-args", "ExtractAudio+ffmpeg:-progress \"${File(outDir, "ffmpeg.progress").path}\"") +
                url,
            cmd,
        )
        assertFalse(cmd.contains("-S"))
        assertFalse(cmd.contains("--merge-output-format"))
    }

    @Test
    fun download_cover() {
        val cmd = command(Quality.COVER)
        assertEquals(
            common + listOf("--skip-download", "--write-thumbnail", "--convert-thumbnails", "jpg") + url,
            cmd,
        )
        assertFalse(cmd.contains("-f"))
        assertFalse(cmd.contains("-S"))
        assertFalse(cmd.contains("--merge-output-format"))
        assertFalse(cmd.contains("-x"))
    }

    @Test
    fun download_aria2cOnAddsDownloaderAndItsArgsBeforeUrl() {
        for (quality in Quality.values()) {
            val on = command(quality, useAria2c = true)
            val off = command(quality, useAria2c = false)
            assertEquals(off.dropLast(1) + listOf("--downloader", "libaria2c.so") + aria2cArgs + url, on)
        }
    }

    @Test
    fun download_aria2cIsSkippedForYouTubeHosts() {
        val links = listOf(
            "https://youtube.com/watch?v=abc",
            "https://www.youtube.com/watch?v=abc",
            "https://m.youtube.com/watch?v=abc",
            "https://music.youtube.com/watch?v=abc",
            "https://youtu.be/abc",
            "https://www.youtube-nocookie.com/embed/abc",
            "https://WWW.YouTube.com/watch?v=abc",
            "https://www.youtube.com./watch?v=abc",
            "https://www.youtube.com/watch?v=abc|def",
        )
        for (link in links) {
            val on = command(Quality.BEST, useAria2c = true, link = link)
            assertEquals(link, command(Quality.BEST, useAria2c = false, link = link), on)
        }
    }

    @Test
    fun download_aria2cStaysOnForOtherHostsEvenWhenTheyMentionYouTube() {
        val links = listOf(
            "https://vimeo.com/123",
            "https://notyoutube.com/watch?v=abc",
            "https://youtube.com.evil.example/watch?v=abc",
            "https://youtube.com@evil.example/watch?v=abc",
            "https://evil.example/youtube.com/watch?v=abc",
            "https://evil.example/?u=https://youtu.be/abc",
            "https://fakeyoutu.be/abc",
            "https://youtube.company/abc",
        )
        for (link in links) {
            val on = command(Quality.BEST, useAria2c = true, link = link)
            val off = command(Quality.BEST, useAria2c = false, link = link)
            assertEquals(link, off.dropLast(1) + listOf("--downloader", "libaria2c.so") + aria2cArgs + link, on)
        }
    }

    @Test
    fun download_aria2cOffNeverMentionsAria2c() {
        for (quality in Quality.values()) {
            val cmd = command(quality, useAria2c = false)
            assertFalse(cmd.contains("--downloader"))
            assertFalse(cmd.contains("--downloader-args"))
            assertFalse(cmd.any { it.contains("aria2c") })
        }
    }

    @Test
    fun download_aria2cSendsOneCombinedArgsValueAfterTheDownloader() {
        val cmd = command(Quality.BEST, useAria2c = true)
        assertEquals(1, cmd.count { it == "--downloader-args" })
        assertTrue(cmd.indexOf("--downloader-args") > cmd.indexOf("--downloader"))
        assertFalse(cmd.contains("--external-downloader-args"))
        assertFalse(cmd.contains("--external-downloader"))
    }

    // The library adds two --external-downloader-args at execute and yt-dlp keeps only the last one per downloader.
    @Test
    fun download_aria2cArgsComeAfterWhatTheLibraryAddsAtExecute() {
        val cmd = RequestBuilder.download(request(Quality.BEST, useAria2c = true), outDir, cacheDir, noBackupDir)
            .addOption("--external-downloader-args", "aria2c:--summary-interval=1")
            .addOption("--external-downloader-args", "aria2c:--ca-certificate=$caCert")
            .buildCommand()
        assertEquals(aria2cArgs, cmd.subList(cmd.size - 3, cmd.size - 1))
        assertTrue(cmd.lastIndexOf("--external-downloader-args") < cmd.indexOf("--downloader-args"))
    }

    @Test
    fun download_keepsUrlAsSingleFinalArgument() {
        for (quality in Quality.values()) {
            val cmd = command(quality)
            assertEquals(url, cmd.last())
            assertEquals(1, cmd.count { it == url })
        }
    }

    @Test
    fun download_writesOnlyUnderOutDirAndIgnoresFolder() {
        val evil = request(Quality.BEST).copy(folder = "../../evil")
        val cmd = RequestBuilder.download(evil, outDir, cacheDir, noBackupDir).buildCommand()
        assertTrue(cmd.none { it.contains("evil") })
        assertEquals(template, cmd[cmd.indexOf("-o") + 1])
    }

    @Test
    fun download_rejectsNonHttpUrl() {
        for (bad in listOf("", "file:///etc/passwd", "--exec x", "example.com")) {
            assertInvalidUrl {
                RequestBuilder.download(request(Quality.BEST, link = bad), outDir, cacheDir, noBackupDir)
            }
        }
    }

    @Test
    fun convert_pointsYtDlpAtTheCopyAndSavesTheMp3BesideIt() {
        val source = File(outDir, "My clip [x] #1.mp4").absoluteFile
        val cmd = RequestBuilder.convert(source, cacheDir).buildCommand()
        val dir = source.parentFile!!
        assertEquals(
            listOf(
                "--enable-file-urls", "--no-mtime", "--cache-dir", ytDlpCache,
                "-o", File(dir, "My clip [x] #1.%(ext)s").path,
                "-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "0",
                "--postprocessor-args", "ExtractAudio+ffmpeg:-progress \"${File(dir, "ffmpeg.progress").path}\"",
            ),
            cmd.dropLast(1),
        )
        // Percent-encoded, so the space, brackets and # stay part of the path.
        val link = cmd.last()
        assertTrue(link, link.startsWith("file:///"))
        assertTrue(link, link.endsWith("/My%20clip%20%5Bx%5D%20%231.mp4"))
        assertEquals(source.path, File(java.net.URI(link)).path)
    }

    @Test
    fun safeFileName_dropsWhatAFileSystemOrTheTemplateWouldMisread() {
        assertEquals("My clip [x]", RequestBuilder.safeFileName("My clip [x]"))
        assertEquals("ab 100 done", RequestBuilder.safeFileName("a/b 100% done"))
        assertEquals("rm", RequestBuilder.safeFileName("--rm"))
        assertEquals("hidden", RequestBuilder.safeFileName("..hidden"))
        assertEquals("video", RequestBuilder.safeFileName("///"))
        assertEquals(150, RequestBuilder.safeFileName("x".repeat(300)).length)
    }
}
