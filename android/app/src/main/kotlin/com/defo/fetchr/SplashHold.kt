package com.defo.fetchr

import java.time.Duration
import java.time.Instant

private const val MAX_HOLD_MS = 1000L

object SplashHold {
    // How long the system splash icon animation still has to run. A null start or duration is a splash with no
    // animated icon, and EPOCH is an animation that had not started when the view was copied; neither is worth
    // holding the splash for. The cap keeps a clock or platform oddity from freezing the launch.
    fun remainingMs(start: Instant?, duration: Duration?, now: Instant): Long {
        if (start == null || duration == null || start == Instant.EPOCH) return 0L
        return (duration.toMillis() - Duration.between(start, now).toMillis()).coerceIn(0L, MAX_HOLD_MS)
    }
}
