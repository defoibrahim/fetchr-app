package com.defo.fetchr

import com.defo.fetchr.pigeon.Quality

// What a download is to the system: picks its MediaStore collection, folder and mime type.
enum class MediaKind(val mimePrefix: String, val defaultMime: String) {
    VIDEO("video/", "video/mp4"),
    AUDIO("audio/", "audio/mpeg"),
    IMAGE("image/", "image/jpeg"),
}

internal val Quality.mediaKind: MediaKind
    get() = when (this) {
        Quality.MP3 -> MediaKind.AUDIO
        Quality.COVER -> MediaKind.IMAGE
        Quality.BEST, Quality.P1080, Quality.P720, Quality.P480 -> MediaKind.VIDEO
    }
