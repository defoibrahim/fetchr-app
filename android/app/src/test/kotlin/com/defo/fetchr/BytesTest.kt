package com.defo.fetchr

import org.junit.Assert.assertEquals
import org.junit.Test

class BytesTest {
    private val kib = 1_024L
    private val mib = kib * 1_024
    private val gib = mib * 1_024

    @Test
    fun formatBoundaries() {
        assertEquals("0 B", Bytes.format(0))
        assertEquals("0 B", Bytes.format(-5))
        assertEquals("999 B", Bytes.format(999))
        assertEquals("1.5 KB", Bytes.format(1_536))
        assertEquals("6.2 MB", Bytes.format((6.2 * mib).toLong()))
        assertEquals("96 MB", Bytes.format(96 * mib))
        assertEquals("1.2 GB", Bytes.format((1.2 * gib).toLong()))
    }

    @Test
    fun roundingToTenDropsTheDecimal() {
        assertEquals("10 MB", Bytes.format((9.96 * mib).toLong()))
        assertEquals("9.9 MB", Bytes.format((9.9 * mib).toLong()))
    }

    @Test
    fun roundingToAThousandAndTwentyFourMovesUpAUnit() {
        assertEquals("1.0 MB", Bytes.format(mib - 1))
        assertEquals("1.0 KB", Bytes.format(kib))
    }

    @Test
    fun speedAddsThePerSecondSuffix() {
        assertEquals("4.2 MB/s", Bytes.speed((4.2 * mib).toLong()))
        assertEquals("1.0 KB/s", Bytes.speed(kib))
    }
}
