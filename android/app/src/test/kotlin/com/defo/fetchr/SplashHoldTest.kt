package com.defo.fetchr

import java.time.Duration
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

class SplashHoldTest {
    private val start = Instant.ofEpochMilli(1_000_000L)
    private val now = start.plusMillis(200)

    @Test
    fun holdsForWhatIsLeftOfTheAnimation() {
        assertEquals(600L, SplashHold.remainingMs(start, Duration.ofMillis(800), now))
    }

    @Test
    fun releasesOnceTheAnimationIsOver() {
        assertEquals(0L, SplashHold.remainingMs(start, Duration.ofMillis(800), start.plusMillis(800)))
        assertEquals(0L, SplashHold.remainingMs(start, Duration.ofMillis(800), start.plusSeconds(5)))
    }

    @Test
    fun doesNotHoldWithoutAnAnimatedIcon() {
        assertEquals(0L, SplashHold.remainingMs(null, Duration.ofMillis(800), now))
        assertEquals(0L, SplashHold.remainingMs(start, null, now))
        assertEquals(0L, SplashHold.remainingMs(start, Duration.ZERO, now))
    }

    @Test
    fun doesNotHoldForAnAnimationThatHadNotStarted() {
        assertEquals(0L, SplashHold.remainingMs(Instant.EPOCH, Duration.ofMillis(800), now))
    }

    @Test
    fun capsTheHold() {
        assertEquals(1000L, SplashHold.remainingMs(start, Duration.ofSeconds(10), now))
    }

    @Test
    fun aStartInTheFutureStaysWithinTheCap() {
        assertEquals(1000L, SplashHold.remainingMs(start.plusSeconds(60), Duration.ofMillis(800), now))
    }
}
