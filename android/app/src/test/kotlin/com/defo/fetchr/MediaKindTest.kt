package com.defo.fetchr

import com.defo.fetchr.pigeon.Quality
import org.junit.Assert.assertEquals
import org.junit.Test

class MediaKindTest {
    @Test
    fun everyQualityHasOneKind() {
        val expected = mapOf(
            Quality.BEST to MediaKind.VIDEO,
            Quality.P1080 to MediaKind.VIDEO,
            Quality.P720 to MediaKind.VIDEO,
            Quality.P480 to MediaKind.VIDEO,
            Quality.MP3 to MediaKind.AUDIO,
            Quality.COVER to MediaKind.IMAGE,
        )

        assertEquals(expected, Quality.values().associateWith { it.mediaKind })
    }

    @Test
    fun defaultMimeMatchesThePrefix() {
        for (kind in MediaKind.values()) {
            assertEquals(true, kind.defaultMime.startsWith(kind.mimePrefix))
        }
        assertEquals("image/jpeg", MediaKind.IMAGE.defaultMime)
    }
}
