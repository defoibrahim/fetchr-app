package com.defo.fetchr

import com.defo.fetchr.pigeon.FormatOption
import com.defo.fetchr.pigeon.Quality
import org.json.JSONException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class InfoParserTest {
    private val url = "https://example.com/watch?v=abc"
    private val tiers = listOf(Quality.BEST, Quality.P1080, Quality.P720, Quality.P480, Quality.MP3)

    private fun fixture(name: String): String {
        val resource = checkNotNull(javaClass.classLoader?.getResource("info/$name")) { "missing fixture $name" }
        return resource.readText()
    }

    private fun options(vararg formats: String, duration: String = "100"): List<FormatOption> =
        InfoParser.parse(
            """{"_type":"video","duration":$duration,"formats":[${formats.joinToString(",")}]}""",
            url,
        ).options

    private fun video(
        width: Int,
        height: Int,
        vcodec: String = "avc1.4D401F",
        acodec: String = "none",
        extra: String = "",
    ) = """{"vcodec":"$vcodec","acodec":"$acodec","width":$width,"height":$height$extra}"""

    private fun audio(acodec: String = "opus", extra: String = "") =
        """{"vcodec":"none","acodec":"$acodec"$extra}"""

    private fun size(bytes: Long) = ""","filesize":$bytes"""

    private fun List<FormatOption>.qualities() = map { it.quality }

    private fun List<FormatOption>.of(quality: Quality) = single { it.quality == quality }

    private fun bare(vararg qualities: Quality) =
        qualities.map { FormatOption(quality = it, sizeIsEstimate = false) }

    @Test
    fun hdVideoFixtureSumsVideoAndAudioPerTier() {
        val info = InfoParser.parse(fixture("video.json"), url)

        assertEquals(url, info.url)
        assertEquals("Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film", info.title)
        assertEquals("https://i.ytimg.com/vi_webp/aqz-KE-bpKQ/maxresdefault.webp", info.thumbnail)
        assertEquals(635L, info.durationSeconds)
        assertEquals("Blender", info.uploader)
        assertFalse(info.isPlaylist)
        assertTrue(info.entries.isEmpty())

        // Each video-only pick is merged with m4a 140 (10_271_496 bytes), which beats the larger opus stream.
        assertEquals(
            listOf(
                FormatOption(Quality.BEST, 3840, 2160, 60.0, 712_445_280L + 10_271_496L, false),
                FormatOption(Quality.P1080, 1920, 1080, 60.0, 257_619_653L + 10_271_496L, false),
                FormatOption(Quality.P720, 1280, 720, 60.0, 150_524_867L + 10_271_496L, false),
                FormatOption(Quality.P480, 854, 480, 30.0, 28_207_144L + 10_271_496L, false),
                FormatOption(Quality.MP3, sizeBytes = 10_271_496L, sizeIsEstimate = true),
                FormatOption(Quality.COVER, 1920, 1080, null, null, false),
            ),
            info.options,
        )
    }

    @Test
    fun lowResVideoCollapsesEveryTierIntoBest() {
        val info = InfoParser.parse(fixture("video_low_res.json"), url)

        assertEquals("Me at the zoo", info.title)
        assertEquals(19L, info.durationSeconds)
        assertEquals("jawed", info.uploader)
        // 320x240 avc1 (322_379) plus m4a 140 (309_288); the thumbnail has no matching entry, so no size.
        assertEquals(
            listOf(
                FormatOption(Quality.BEST, 320, 240, 15.0, 322_379L + 309_288L, false),
                FormatOption(Quality.MP3, sizeBytes = 309_288L, sizeIsEstimate = true),
                FormatOption(Quality.COVER, sizeIsEstimate = false),
            ),
            info.options,
        )
    }

    @Test
    fun audioOnlyFixtureOffersMp3SizedFromTheBestStreamAndRoundsDuration() {
        val info = InfoParser.parse(fixture("audio_only.json"), url)

        assertEquals("Flickermood", info.title)
        assertEquals("Forss", info.uploader)
        assertEquals(214L, info.durationSeconds)
        assertEquals("https://i1.sndcdn.com/artworks-000067273316-smsiqx-original.jpg", info.thumbnail)
        assertEquals(listOf(Quality.MP3, Quality.COVER), info.options.qualities())
        assertEquals(4_277_720L, info.options.of(Quality.MP3).sizeBytes)
        assertTrue(info.options.of(Quality.MP3).sizeIsEstimate)
        assertFalse(info.isPlaylist)
    }

    @Test
    fun verticalTikTokCapsTheShortSide() {
        val info = InfoParser.parse(fixture("tiktok_vertical.json"), url)

        assertEquals(17L, info.durationSeconds)
        // 1080p is the same short side as best and is dropped; 480p has nothing under it and takes 576x1024.
        assertEquals(
            listOf(Quality.BEST, Quality.P720, Quality.P480, Quality.MP3, Quality.COVER),
            info.options.qualities(),
        )
        assertEquals(FormatOption(Quality.BEST, 1080, 1920, null, 2_889_649L, false), info.options.of(Quality.BEST))
        assertEquals(FormatOption(Quality.P720, 720, 1280, null, 1_887_507L, false), info.options.of(Quality.P720))
        // Two h264 and one h265 stream share 576x1024; h264 wins and its higher bitrate beats the lower one.
        assertEquals(FormatOption(Quality.P480, 576, 1024, null, 2_593_394L, false), info.options.of(Quality.P480))
        // The only audio-only stream reports no size and no bitrate.
        assertEquals(FormatOption(Quality.MP3, sizeIsEstimate = true), info.options.of(Quality.MP3))
        assertEquals(FormatOption(Quality.COVER, sizeIsEstimate = false), info.options.of(Quality.COVER))
    }

    @Test
    fun playlistFixtureMapsEntriesAndOffersEveryQualityWithoutMetadata() {
        val info = InfoParser.parse(fixture("playlist.json"), url)

        assertTrue(info.isPlaylist)
        assertEquals("Google - Year In Search (unofficial)", info.title)
        assertEquals("Google", info.uploader)
        assertNull(info.durationSeconds)
        assertTrue(info.thumbnail!!.endsWith("rs=AOn4CLC_2pbn1Z9xFNrPS46CiimPR3-zRA"))
        assertEquals(bare(*tiers.toTypedArray()), info.options)
        assertEquals(5, info.entries.size)

        val first = info.entries[0]
        assertEquals("https://www.youtube.com/watch?v=KIViy7L_lo8", first.url)
        assertEquals("2016 — Year in Search", first.title)
        assertEquals(121L, first.durationSeconds)
        assertTrue("last thumbnail wins", first.thumbnail!!.endsWith("rs=AOn4CLABzVEqTkQPeGIcYHNPL7D31C1p-g"))
        assertEquals("El año en búsquedas 2014", info.entries[3].title)
    }

    @Test
    fun playlistEntryWithNullTitleAndDurationKeepsUrlAsTitle() {
        val entry = InfoParser.parse(fixture("playlist.json"), url).entries[2]

        assertEquals("https://www.youtube.com/watch?v=mt7rGhAm2CY", entry.url)
        assertEquals(entry.url, entry.title)
        assertNull(entry.durationSeconds)
        assertTrue(entry.thumbnail!!.startsWith("https://i.ytimg.com/vi/mt7rGhAm2CY/"))
    }

    @Test
    fun jsonNullComesBackAsNull() {
        val info = InfoParser.parse(
            """{"_type":"video","title":null,"thumbnail":null,"duration":null,"uploader":null,"formats":null}""",
            url,
        )

        assertEquals(url, info.title)
        assertNull(info.thumbnail)
        assertNull(info.durationSeconds)
        assertNull(info.uploader)
        assertEquals(bare(*tiers.toTypedArray()), info.options)
    }

    @Test
    fun missingKeysComeBackAsNull() {
        val info = InfoParser.parse("{}", url)

        assertEquals(url, info.title)
        assertNull(info.thumbnail)
        assertNull(info.durationSeconds)
        assertNull(info.uploader)
        assertFalse(info.isPlaylist)
    }

    @Test
    fun liveStreamIsFlagged() {
        assertTrue(InfoParser.parse("""{"_type":"video","is_live":true}""", url).isLive)
    }

    @Test
    fun isLiveDefaultsToFalse() {
        assertFalse(InfoParser.parse("{}", url).isLive)
        assertFalse(InfoParser.parse("""{"is_live":null}""", url).isLive)
        assertFalse(InfoParser.parse(fixture("video.json"), url).isLive)
        assertFalse(InfoParser.parse(fixture("playlist.json"), url).isLive)
    }

    @Test
    fun nullEntryFieldsStayNull() {
        val json = """{"_type":"playlist","title":"P","entries":[
            {"url":"https://a.test/1","title":null,"thumbnail":null,"thumbnails":null,"duration":null}]}"""
        val entry = InfoParser.parse(json, url).entries.single()

        assertEquals("https://a.test/1", entry.title)
        assertNull(entry.thumbnail)
        assertNull(entry.durationSeconds)
    }

    @Test
    fun thumbnailFallsBackToLastOfThumbnails() {
        val json = """{"thumbnails":[{"url":"https://a.test/small.jpg"},{"url":"https://a.test/big.jpg"}]}"""

        assertEquals("https://a.test/big.jpg", InfoParser.parse(json, url).thumbnail)
    }

    @Test
    fun entryUsesWebpageUrlWhenUrlIsMissing() {
        val json = """{"_type":"playlist","entries":[{"webpage_url":"https://a.test/w","title":"W"}]}"""

        assertEquals("https://a.test/w", InfoParser.parse(json, url).entries.single().url)
    }

    @Test
    fun entriesWithoutAnyUrlAreSkipped() {
        val json = """{"_type":"playlist","entries":[{"title":"no url"},null,{"url":"https://a.test/ok","title":"ok"}]}"""
        val entries = InfoParser.parse(json, url).entries

        assertEquals(listOf("https://a.test/ok"), entries.map { it.url })
    }

    @Test
    fun multiVideoIsAPlaylist() {
        val json = """{"_type":"multi_video","entries":[{"url":"https://a.test/1","title":"one"}]}"""
        val info = InfoParser.parse(json, url)

        assertTrue(info.isPlaylist)
        assertEquals(bare(*tiers.toTypedArray()), info.options)
        assertEquals(1, info.entries.size)
    }

    @Test(expected = JSONException::class)
    fun garbageThrows() {
        InfoParser.parse("ERROR: not json", url)
    }

    @Test
    fun playlistNeverOffersACover() {
        val json = """{"_type":"playlist","thumbnail":"https://a.test/p.jpg","entries":[]}"""

        assertEquals(tiers, InfoParser.parse(json, url).options.qualities())
    }

    @Test
    fun noFormatsOffersEveryQualityWithoutMetadata() {
        assertEquals(bare(*tiers.toTypedArray()), InfoParser.parse("""{"formats":null}""", url).options)
        assertEquals(bare(*tiers.toTypedArray()), InfoParser.parse("""{"formats":[]}""", url).options)
    }

    @Test
    fun coverFollowsTheThumbnailAndTakesItsSizeFromTheMatchingEntry() {
        val withEntry = """{"thumbnail":"https://a.test/t.jpg","thumbnails":[
            {"url":"https://a.test/small.jpg","width":10,"height":10},
            {"url":"https://a.test/t.jpg","width":640,"height":360}]}"""
        val withoutEntry = """{"thumbnail":"https://a.test/other.jpg","thumbnails":[
            {"url":"https://a.test/t.jpg","width":640,"height":360}]}"""
        val none = """{"formats":null}"""

        assertEquals(
            FormatOption(Quality.COVER, 640, 360, null, null, false),
            InfoParser.parse(withEntry, url).options.last(),
        )
        assertEquals(
            FormatOption(Quality.COVER, sizeIsEstimate = false),
            InfoParser.parse(withoutEntry, url).options.last(),
        )
        assertFalse(InfoParser.parse(none, url).options.any { it.quality == Quality.COVER })
    }

    @Test
    fun coverIsOfferedWhenOnlyTheThumbnailsListHasAnImage() {
        val json = """{"thumbnails":[{"url":"https://a.test/big.jpg"}]}"""

        assertEquals(Quality.COVER, InfoParser.parse(json, url).options.last().quality)
    }

    @Test
    fun onlyNoneVideoCodecsOffersMp3Only() {
        val storyboard = """{"vcodec":"none","acodec":"none","width":320,"height":180}"""

        assertEquals(
            listOf(FormatOption(Quality.MP3, sizeBytes = 1000L, sizeIsEstimate = true)),
            options(audio(extra = size(1000)), storyboard),
        )
    }

    @Test
    fun storyboardsAloneStillOfferMp3WithoutASize() {
        val storyboard = """{"vcodec":"none","acodec":"none","width":320,"height":180}"""

        assertEquals(listOf(FormatOption(Quality.MP3, sizeIsEstimate = true)), options(storyboard))
    }

    @Test
    fun videoWithoutDimensionsOffersBestAndMp3WithoutMetadata() {
        val noSize = """{"vcodec":"avc1.4D401F","acodec":"mp4a.40.2"}"""
        val nullSize = """{"vcodec":"avc1.4D401F","height":null,"width":null}"""
        val heightOnly = """{"vcodec":"avc1.4D401F","acodec":"mp4a.40.2","height":720}"""

        assertEquals(
            bare(Quality.BEST) + FormatOption(Quality.MP3, sizeIsEstimate = true),
            options(noSize),
        )
        assertEquals(
            bare(Quality.BEST) + FormatOption(Quality.MP3, sizeBytes = 500L, sizeIsEstimate = true),
            options(audio(extra = size(500)), nullSize),
        )
        assertEquals(listOf(Quality.BEST, Quality.MP3), options(heightOnly).qualities())
    }

    @Test
    fun videoOnlyWithoutAnyAudioOffersNoMp3() {
        assertEquals(listOf(Quality.BEST), options(video(1280, 720)).qualities())
    }

    @Test
    fun missingVideoCodecCountsAsVideoWithSoundUnknown() {
        val offered = options("""{"width":1280,"height":720}""")

        assertEquals(listOf(Quality.BEST, Quality.MP3), offered.qualities())
        assertEquals(1280L, offered.first().width)
        assertEquals(720L, offered.first().height)
    }

    @Test
    fun aSingleStreamCollapsesEveryTierIntoBest() {
        for ((width, height) in listOf(1920 to 1080, 1080 to 1920, 2560 to 1440, 320 to 240)) {
            val offered = options(video(width, height), audio()).qualities()

            assertEquals("${width}x$height", listOf(Quality.BEST, Quality.MP3), offered)
        }
    }

    @Test
    fun capsUseTheShorterSideForLandscapeAndPortrait() {
        val landscape = options(video(2560, 1440), video(1920, 1080), video(1280, 720), video(854, 480), audio())
        val portrait = options(video(1440, 2560), video(1080, 1920), video(720, 1280), video(480, 854), audio())

        for (offered in listOf(landscape, portrait)) {
            assertEquals(tiers, offered.qualities())
            val shortSides = offered.filter { it.quality != Quality.MP3 }.map { minOf(it.width!!, it.height!!) }
            assertEquals(listOf(1440L, 1080L, 720L, 480L), shortSides)
        }
    }

    @Test
    fun aTierWithNothingUnderItsCapTakesTheSmallestStreamAbove() {
        val offered = options(video(1080, 1920), video(576, 1024), audio())

        assertEquals(listOf(Quality.BEST, Quality.P720, Quality.MP3), offered.qualities())
        assertEquals(576L, offered.of(Quality.P720).width)
    }

    @Test
    fun aStreamAboveItsCapIsNotPickedWhileOneFits() {
        val offered = options(video(1920, 1080), video(1280, 720), audio())

        assertEquals(listOf(Quality.BEST, Quality.P720, Quality.MP3), offered.qualities())
        assertEquals(1920L, offered.of(Quality.BEST).width)
        assertEquals(1280L, offered.of(Quality.P720).width)
    }

    @Test
    fun storyboardDimensionsAreIgnored() {
        val storyboard = """{"vcodec":"none","acodec":"none","width":1920,"height":1080}"""

        val offered = options(storyboard, video(1280, 720), audio())

        assertEquals(720L, offered.of(Quality.BEST).height)
        assertEquals(listOf(Quality.BEST, Quality.MP3), offered.qualities())
    }

    @Test
    fun h264BeatsHigherBitrateOnTheSameShortSide() {
        fun stream(vcodec: String, bytes: Long, tbr: Int) =
            video(1280, 720, vcodec = vcodec, acodec = "aac", extra = size(bytes) + ""","tbr":$tbr""")
        val vp9 = stream("vp09.00.40.08", 900, 3000)
        val h264 = stream("avc1.64001F", 100, 500)
        val legacy = stream("h264", 300, 100)

        assertEquals(100L, options(vp9, h264).of(Quality.BEST).sizeBytes)
        // avc1 and h264 are the same codec to yt-dlp, so the larger size decides.
        assertEquals(300L, options(h264, legacy).of(Quality.BEST).sizeBytes)
        assertEquals(300L, options(vp9, legacy).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun withoutH264TheCodecClosestToItWins() {
        fun stream(vcodec: String, bytes: Long, tbr: Int) =
            video(3840, 2160, vcodec = vcodec, acodec = "aac", extra = size(bytes) + ""","tbr":$tbr""")
        val vp9 = stream("vp09.00.50.08", 100, 8000)
        val av1 = stream("av01.0.12M.08", 200, 12000)
        val hevc = stream("hvc1.1.6.L153", 300, 6000)
        val vp8 = stream("vp8", 400, 1000)

        assertEquals(100L, options(vp9, av1).of(Quality.BEST).sizeBytes)
        assertEquals(300L, options(vp9, av1, hevc).of(Quality.BEST).sizeBytes)
        assertEquals(400L, options(vp9, hevc, vp8).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun aProgressiveAacStreamBeatsAFasterVideoOnlyOneOfTheSameCodec() {
        val progressive = video(1280, 720, acodec = "mp4a.40.2", extra = size(1000) + ""","fps":30""")
        val videoOnly = video(1280, 720, extra = size(900) + ""","fps":60""")

        val best = options(progressive, videoOnly, audio("mp4a.40.2", size(300))).of(Quality.BEST)

        assertEquals(1000L, best.sizeBytes)
        assertEquals(30.0, best.fps)
    }

    @Test
    fun frameRateThenSizeThenBitrateBreakTheTie() {
        fun stream(bytes: Long, fps: Int, tbr: Int) =
            video(1280, 720, acodec = "aac", extra = size(bytes) + ""","fps":$fps,"tbr":$tbr""")
        val slow = stream(10, 30, 5000)
        val fast = stream(20, 60, 100)
        val fastHeavy = stream(30, 60, 200)

        assertEquals(20L, options(slow, fast).of(Quality.BEST).sizeBytes)
        assertEquals(30L, options(slow, fast, fastHeavy).of(Quality.BEST).sizeBytes)
        assertEquals(60.0, options(slow, fast).of(Quality.BEST).fps)

        // No sizes at all: the bitrate decides, and the size is its estimate (kbit/s x 125 x 100 s).
        val low = video(1280, 720, acodec = "aac", extra = ""","tbr":100""")
        val high = video(1280, 720, acodec = "aac", extra = ""","tbr":200""")
        assertEquals(2_500_000L, options(low, high).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun videoOnlyPickIsMergedWithTheBestAudio() {
        val v = video(1280, 720, extra = size(1000))
        val opusLoud = audio("opus", size(400) + ""","abr":160""")
        val aacQuiet = audio("mp4a.40.2", size(300) + ""","abr":128""")
        val aacLouder = audio("mp4a.40.2", size(350) + ""","abr":140""")

        assertEquals(1300L, options(v, opusLoud, aacQuiet).of(Quality.BEST).sizeBytes)
        assertEquals(1350L, options(v, opusLoud, aacQuiet, aacLouder).of(Quality.BEST).sizeBytes)
        assertEquals(400L, options(v, opusLoud).of(Quality.MP3).sizeBytes)
    }

    @Test
    fun audioFallsBackToTbrWhenAbrIsMissingOrZero() {
        val v = video(1280, 720, extra = size(1000))
        val small = audio("opus", size(100) + ""","abr":0,"tbr":64""")
        val big = audio("opus", size(200) + ""","abr":0,"tbr":128""")

        assertEquals(1200L, options(v, small, big).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun progressivePickDoesNotAddAudio() {
        val progressive = video(1280, 720, acodec = "mp4a.40.2", extra = size(1000))

        assertEquals(1000L, options(progressive, audio(extra = size(400))).of(Quality.BEST).sizeBytes)
        assertEquals(1000L, options(video(1280, 720, acodec = "aac", extra = size(1000))).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun missingAudioCodecIsTreatedAsProgressive() {
        val unknown = """{"vcodec":"avc1.4D401F","width":1280,"height":720,"filesize":1000}"""

        assertEquals(1000L, options(unknown, audio(extra = size(400))).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun exactSizeIsNotAnEstimate() {
        val offered = options(video(1280, 720, extra = size(1000)), audio(extra = size(200)))

        assertEquals(FormatOption(Quality.BEST, 1280, 720, null, 1200L, false), offered.of(Quality.BEST))
    }

    @Test
    fun approximateSizeIsFlaggedAsAnEstimate() {
        val offered = options(
            video(1280, 720, extra = ""","filesize_approx":1000"""),
            audio(extra = size(200)),
        )

        assertEquals(1200L, offered.of(Quality.BEST).sizeBytes)
        assertTrue(offered.of(Quality.BEST).sizeIsEstimate)
    }

    @Test
    fun exactFilesizeWinsOverTheApproximation() {
        val v = video(1280, 720, extra = size(1000) + ""","filesize_approx":5000""")

        val best = options(v, audio(extra = size(200))).of(Quality.BEST)

        assertEquals(1200L, best.sizeBytes)
        assertFalse(best.sizeIsEstimate)
    }

    @Test
    fun bitrateTimesDurationIsTheLastResort() {
        val v = video(1280, 720, extra = size(1000))
        val a = audio("opus", ""","tbr":64""")

        val best = options(v, a, duration = "10").of(Quality.BEST)

        // 64 kbit/s is 8000 bytes/s.
        assertEquals(1000L + 80_000L, best.sizeBytes)
        assertTrue(best.sizeIsEstimate)
        assertEquals(80_000L, options(v, a, duration = "10").of(Quality.MP3).sizeBytes)
    }

    @Test
    fun bitrateEstimateNeedsADuration() {
        val progressive = video(1280, 720, acodec = "aac", extra = ""","tbr":800""")

        assertNull(options(progressive, duration = "null").of(Quality.BEST).sizeBytes)
        assertEquals(10_000_000L, options(progressive).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun anUnknownPartLeavesTheSizeNull() {
        val v = video(1280, 720, extra = size(1000))

        val best = options(v, audio()).of(Quality.BEST)

        assertNull(best.sizeBytes)
        assertFalse(best.sizeIsEstimate)
        assertNull(options(video(1280, 720), audio(extra = size(200))).of(Quality.BEST).sizeBytes)
    }

    @Test
    fun mp3SizeIsAlwaysAnEstimateAndNullWithoutAudioStream() {
        val progressive = video(1280, 720, acodec = "aac", extra = size(1000))

        assertTrue(options(progressive).of(Quality.MP3).sizeIsEstimate)
        assertNull(options(progressive).of(Quality.MP3).sizeBytes)
        assertEquals(250L, options(progressive, audio(extra = size(250))).of(Quality.MP3).sizeBytes)
    }
}
