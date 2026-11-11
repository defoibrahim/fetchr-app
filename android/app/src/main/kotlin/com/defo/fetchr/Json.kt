package com.defo.fetchr

import kotlin.math.roundToLong
import org.json.JSONObject

// Android's optString returns the text "null" for a JSON null.
internal fun JSONObject.str(key: String): String? = if (isNull(key)) null else optString(key)

// optDouble turns a JSON null into NaN on the JVM and into 0 on Android, so check isNull first.
internal fun JSONObject.num(key: String): Double? =
    if (isNull(key)) null else optDouble(key).takeUnless { it.isNaN() }

// optLong turns a missing key into 0, which a byte count or timestamp cannot tell from a real value; yt-dlp reports fractional durations (213.886).
internal fun JSONObject.long(key: String): Long? = num(key)?.roundToLong()
