package com.defo.fetchr

import com.defo.fetchr.pigeon.FetchrError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class RunGateTest {
    private suspend fun swapError(gate: RunGate): String? =
        try {
            gate.beginSwap()
            null
        } catch (e: FetchrError) {
            e.code
        }

    @Test
    fun swapIsBusyWhileARunIsActive() = runBlocking<Unit> {
        val gate = RunGate()
        gate.enter()
        assertEquals("busy", swapError(gate))
        gate.leave()
        assertNull(swapError(gate))
    }

    @Test
    fun secondSwapIsBusy() = runBlocking<Unit> {
        val gate = RunGate()
        gate.beginSwap()
        assertEquals("busy", swapError(gate))
    }

    @Test
    fun enterWaitsUntilTheSwapEnds() = runBlocking<Unit> {
        val gate = RunGate()
        gate.beginSwap()
        val entered = async(Dispatchers.Default) { gate.enter() }
        delay(100)
        assertFalse(entered.isCompleted)
        gate.endSwap()
        withTimeout(2_000) { entered.await() }
        assertEquals("busy", swapError(gate))
    }
}
