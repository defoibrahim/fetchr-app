package com.defo.fetchr

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Collections

class StartQueueTest {
    private class Runs(val queue: StartQueue) {
        val started: MutableList<String> = Collections.synchronizedList(mutableListOf())
        val release = mutableMapOf<String, CompletableDeferred<Unit>>()

        fun launch(scope: kotlinx.coroutines.CoroutineScope, id: String): Job {
            val ticket = queue.add(id)
            val done = CompletableDeferred<Unit>().also { release[id] = it }
            val job = scope.launch(Dispatchers.Default) {
                queue.withTurn(ticket) {
                    started += id
                    done.await()
                }
            }
            job.invokeOnCompletion { queue.drop(ticket) }
            return job
        }
    }

    private suspend fun until(check: () -> Boolean) = withTimeout(2_000) {
        while (!check()) yield()
    }

    @Test
    fun startsAtMostMaxInLaunchOrder() = runBlocking<Unit> {
        val runs = Runs(StartQueue(2))
        listOf("a", "b", "c").forEach { runs.launch(this, it) }
        until { runs.started.size == 2 }
        assertEquals(listOf("a", "b"), runs.started.toList())
        assertEquals(listOf("c"), runs.queue.order())

        runs.release.getValue("a").complete(Unit)
        until { runs.started.size == 3 }
        runs.release.values.forEach { it.complete(Unit) }
    }

    @Test
    fun reorderChangesWhichWaitingRunStartsNext() = runBlocking<Unit> {
        val runs = Runs(StartQueue(1))
        listOf("a", "b", "c", "d").forEach { runs.launch(this, it) }
        until { runs.started.size == 1 }

        runs.queue.reorder(listOf("d", "b"))
        assertEquals(listOf("d", "c", "b"), runs.queue.order())

        runs.release.getValue("a").complete(Unit)
        until { runs.started.size == 2 }
        assertEquals("d", runs.started[1])
        runs.release.values.forEach { it.complete(Unit) }
    }

    @Test
    fun swapSlotsMovesOnlyTheMovableItemsOfIds() {
        val list = mutableListOf("a", "Q1", "b", "Q2", "Q3")
        list.swapSlots(listOf("Q3", "b", "Q1"), { it }) { it.startsWith("Q") }
        assertEquals(listOf("a", "Q3", "b", "Q2", "Q1"), list)
    }

    @Test
    fun aRunCancelledWhileWaitingGivesItsPlaceUp() = runBlocking<Unit> {
        val runs = Runs(StartQueue(1))
        runs.launch(this, "a")
        val b = runs.launch(this, "b")
        runs.launch(this, "c")
        until { runs.started.size == 1 }

        b.cancel()
        until { runs.queue.order() == listOf("c") }
        runs.release.getValue("a").complete(Unit)
        until { runs.started.size == 2 }
        assertEquals("c", runs.started[1])
        runs.release.values.forEach { it.complete(Unit) }
    }
}
