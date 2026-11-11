package com.defo.fetchr

import android.content.Context
import android.content.SharedPreferences

// The one SharedPreferences file native code owns: the accent here, the yt-dlp check time beside it.
object NativePrefs {
    private const val FILE = "fetchr_native"
    private const val KEY_ACCENT = "accent"
    private val DEFAULT_ACCENT = 0xFFC8F03C.toInt()

    fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // The notification tint, as an ARGB int for setColor.
    fun accent(context: Context): Int = prefs(context).getInt(KEY_ACCENT, DEFAULT_ACCENT)

    // Dart sends the unsigned 32-bit value; a missing alpha would draw the tint invisible.
    fun setAccent(context: Context, argb: Long) {
        prefs(context).edit().putInt(KEY_ACCENT, (argb or 0xFF000000L).toInt()).apply()
    }
}
