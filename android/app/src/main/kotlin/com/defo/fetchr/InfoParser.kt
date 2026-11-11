package com.defo.fetchr

import com.defo.fetchr.pigeon.FormatOption
import com.defo.fetchr.pigeon.PlaylistEntry
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.VideoInfo
import kotlin.math.min
import kotlin.math.roundToLong
import org.json.JSONArray
import org.json.JSONObject

object InfoParser {
    private val VIDEO_TIERS = listOf(Quality.BEST, Quality.P1080, Quality.P720, Quality.P480)

    // yt-dlp's bytes per second for one kbit/s.
    private const val BYTES_PER_KBIT = 125

    private class Size(val bytes: Long, val estimated: Boolean)

    // Throws JSONException on non-JSON output; the caller maps it through ErrorClassifier.
    fun parse(json: String, url: String): VideoInfo {
        val root = JSONObject(json)
        val type = root.str("_type")
        val isPlaylist = type == "playlist" || type == "multi_video"
        return VideoInfo(
            url = url,
            title = root.str("title") ?: url,
            thumbnail = root.thumbnail(),
            durationSeconds = root.long("duration"),
            uploader = root.str("uploader"),
            isPlaylist = isPlaylist,
            options = if (isPlaylist) bare(VIDEO_TIERS + Quality.MP3) else options(root),
            entries = if (isPlaylist) entries(root.optJSONArray("entries")) else emptyList(),
            isLive = root.optBoolean("is_live"),
        )
    }

    // Approximates what yt-dlp downloads for each quality, so the sizes shown match the file saved.
    private fun options(root: JSONObject): List<FormatOption> {
        val cover = listOfNotNull(coverOption(root))
        val formats = objects(root.optJSONArray("formats"))
        if (formats.isEmpty()) return bare(VIDEO_TIERS + Quality.MP3) + cover

        val duration = root.num("duration")
        val audio = formats.filter { it.str("vcodec") == "none" && it.str("acodec") != "none" }
        val bestAudio = audio.maxWithOrNull(AUDIO_ORDER)
        val mp3 = mp3Option(bestAudio, duration)
        val video = formats.filter { it.str("vcodec") != "none" }
        if (video.isEmpty()) return listOf(mp3) + cover

        // A missing acodec means unknown, so only an explicit "none" rules out sound.
        val hasSound = audio.isNotEmpty() || video.any { it.str("acodec") != "none" }
        val extras = listOfNotNull(mp3.takeIf { hasSound }) + cover
        val sized = video.filter { it.dimension("width") > 0 && it.dimension("height") > 0 }
        if (sized.isEmpty()) return bare(listOf(Quality.BEST)) + extras

        val tiers = VIDEO_TIERS
            .map { it to pickVideo(sized, it.shortSideCap) }
            .distinctBy { (_, pick) -> pick.shortSide() }
            .map { (quality, pick) -> videoOption(quality, pick, bestAudio, duration) }
        return tiers + extras
    }

    // Mirrors `-S res:<cap>`: the largest short side within the cap, else the smallest one above it.
    private fun pickVideo(video: List<JSONObject>, cap: Int?): JSONObject {
        val sides = video.map { it.shortSide() }
        val side = if (cap == null) sides.max() else sides.filter { it <= cap }.maxOrNull() ?: sides.min()
        return video.filter { it.shortSide() == side }.maxWith(VIDEO_ORDER)
    }

    private fun videoOption(
        quality: Quality,
        pick: JSONObject,
        bestAudio: JSONObject?,
        duration: Double?,
    ): FormatOption {
        // A video-only pick is merged with the best audio stream, so both count toward the size.
        val parts = listOfNotNull(pick, bestAudio.takeIf { pick.str("acodec") == "none" })
        val known = parts.mapNotNull { it.size(duration) }
        return FormatOption(
            quality = quality,
            width = pick.long("width"),
            height = pick.long("height"),
            fps = pick.num("fps"),
            sizeBytes = if (known.size == parts.size) known.sumOf { it.bytes } else null,
            sizeIsEstimate = known.any { it.estimated },
        )
    }

    private fun mp3Option(bestAudio: JSONObject?, duration: Double?) = FormatOption(
        quality = Quality.MP3,
        sizeBytes = bestAudio?.size(duration)?.bytes,
        sizeIsEstimate = true,
    )

    private fun coverOption(root: JSONObject): FormatOption? {
        val url = root.thumbnail() ?: return null
        val match = objects(root.optJSONArray("thumbnails")).firstOrNull { it.str("url") == url }
        return FormatOption(
            quality = Quality.COVER,
            width = match?.long("width"),
            height = match?.long("height"),
            sizeIsEstimate = false,
        )
    }

    private fun bare(qualities: List<Quality>) = qualities.map { FormatOption(quality = it, sizeIsEstimate = false) }

    private val AUDIO_ORDER = compareBy<JSONObject>(
        { it.str("acodec")?.startsWith("mp4a") == true },
        { it.positive("abr") ?: it.positive("tbr") ?: 0.0 },
    )

    // yt-dlp's codec preference lists, best first: "" is any other codec and null a missing one.
    private val VCODECS = listOf(
        "av0?1", "vp0?9.2", "vp0?9", "[hx]265|he?vc?", "[hx]264|avc", "vp0?8", "mp4v|h263", "theora", "", null, "none",
    )
    private val ACODECS = listOf(
        "[af]lac", "wav|aiff", "opus", "vorbis|ogg", "aac", "mp?4a?", "mp3", "ac-?4", "e-?a?c-?3", "ac-?3", "dts",
        "", null, "none",
    )

    // Within one short side: `-S vcodec:h264,acodec:aac`, then yt-dlp's defaults (frame rate, size, bitrate).
    private val VIDEO_ORDER = compareBy<JSONObject>(
        { codecRank(VCODECS, "h264", it.str("vcodec")) },
        { codecRank(ACODECS, "aac", it.str("acodec")) },
        { it.num("fps") ?: 0.0 },
        { it.positive("filesize") ?: it.positive("filesize_approx") ?: 0.0 },
        { it.num("tbr") ?: 0.0 },
    )

    // `-S <field>:<limit>`: codecs at or below the limit win, closest first, then those above it, closest first.
    private fun codecRank(order: List<String?>, limit: String, codec: String?): Int {
        val at = codecIndex(order, codec)
        return if (at >= codecIndex(order, limit)) order.size - at else at - order.size
    }

    private fun codecIndex(order: List<String?>, codec: String?): Int {
        if (codec == null) return order.indexOf(null)
        val name = codec.lowercase()
        val hit = order.indexOfFirst { !it.isNullOrEmpty() && Regex("^(?:$it)").containsMatchIn(name) }
        return if (hit >= 0) hit else order.indexOf("")
    }

    private fun JSONObject.positive(key: String): Double? = num(key)?.takeIf { it > 0 }

    private fun JSONObject.dimension(key: String): Long = long(key) ?: 0L

    private fun JSONObject.shortSide(): Long = min(dimension("width"), dimension("height"))

    private fun JSONObject.size(duration: Double?): Size? =
        positive("filesize")?.let { Size(it.roundToLong(), estimated = false) }
            ?: positive("filesize_approx")?.let { Size(it.roundToLong(), estimated = true) }
            ?: bitrateSize(duration)

    private fun JSONObject.bitrateSize(duration: Double?): Size? {
        val kbit = positive("tbr") ?: positive("abr") ?: return null
        return duration?.let { Size((kbit * it * BYTES_PER_KBIT).roundToLong(), estimated = true) }
    }

    private fun entries(array: JSONArray?): List<PlaylistEntry> = objects(array).mapNotNull { e ->
        val entryUrl = e.str("url") ?: e.str("webpage_url") ?: return@mapNotNull null
        PlaylistEntry(
            url = entryUrl,
            title = e.str("title") ?: entryUrl,
            thumbnail = e.thumbnail(),
            durationSeconds = e.long("duration"),
        )
    }

    private fun objects(array: JSONArray?): List<JSONObject> =
        if (array == null) emptyList() else (0 until array.length()).mapNotNull { array.optJSONObject(it) }

    // yt-dlp sorts thumbnails worst to best, so the last one is the largest.
    private fun JSONObject.thumbnail(): String? =
        str("thumbnail") ?: objects(optJSONArray("thumbnails")).lastOrNull()?.str("url")
}
