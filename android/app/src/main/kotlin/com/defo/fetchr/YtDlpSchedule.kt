package com.defo.fetchr

internal object YtDlpSchedule {
    private const val INTERVAL_MS = 24L * 60 * 60 * 1000

    // Due when enabled and 24 h have passed since the last check, or the clock moved back.
    fun isDue(lastCheckedMs: Long, nowMs: Long, enabled: Boolean): Boolean {
        if (!enabled) return false
        val elapsed = nowMs - lastCheckedMs
        return elapsed < 0 || elapsed >= INTERVAL_MS
    }
}
