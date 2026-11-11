package com.defo.fetchr

import java.util.Locale

// The size rule of Dart's formatBytes: one decimal below 10, none from 10.
internal object Bytes {
    private val units = listOf("B", "KB", "MB", "GB", "TB")

    fun format(bytes: Long): String {
        if (bytes <= 0) return "0 B"
        var value = bytes.toDouble()
        var unit = 0
        // Compares the text that is shown, so 1048575 reads 1.0 MB instead of 1024 KB.
        while (number(value).toDouble() >= 1024 && unit < units.lastIndex) {
            value /= 1024
            unit++
        }
        return if (unit == 0) "$bytes B" else "${number(value)} ${units[unit]}"
    }

    fun speed(bytesPerSec: Long): String = "${format(bytesPerSec)}/s"

    // Rounding to one decimal can reach 10 (9.96), which then drops its decimal too. Locale.ROOT keeps ASCII digits.
    private fun number(value: Double): String {
        val oneDecimal = String.format(Locale.ROOT, "%.1f", value)
        return if (oneDecimal.toDouble() >= 10) String.format(Locale.ROOT, "%.0f", value) else oneDecimal
    }
}
