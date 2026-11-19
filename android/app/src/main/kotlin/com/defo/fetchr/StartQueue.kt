package com.defo.fetchr

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update

// Starts at most [max] runs at once, in an order the user can change. A semaphore starts its waiters in arrival
// order, which a reorder cannot touch.
internal class StartQueue(private val max: Int) {
    // A run's place; an id alone is not enough, as a resumed task's new run can queue before its old one is gone.
    class Ticket(val id: String)

    private val waiting = mutableListOf<Ticket>()
    private var running = 0
    private val changes = MutableStateFlow(0L)

    // Called when the run is launched, not when it reaches its turn, so a reorder sent right after sees it.
    @Synchronized
    fun add(id: String): Ticket = Ticket(id).also { waiting += it }

    // A run that ends before its turn (cancelled, paused, removed) gives its place up here.
    fun drop(ticket: Ticket) {
        val removed = synchronized(this) { waiting.remove(ticket) }
        if (removed) changes.update { it + 1 }
    }

    // The waiting runs of [ids] take the places those runs held, in the order of [ids]; the rest keep theirs.
    fun reorder(ids: List<String>) {
        synchronized(this) { waiting.swapSlots(ids, Ticket::id) }
        changes.update { it + 1 }
    }

    @Synchronized
    fun order(): List<String> = waiting.map { it.id }

    suspend fun <T> withTurn(ticket: Ticket, block: suspend () -> T): T {
        changes.first { tryStart(ticket) }
        // The next in line is now at the head; it may have looked before, and a free slot may be waiting for it.
        changes.update { it + 1 }
        try {
            return block()
        } finally {
            synchronized(this) { running-- }
            changes.update { it + 1 }
        }
    }

    @Synchronized
    private fun tryStart(ticket: Ticket): Boolean {
        if (running >= max || waiting.firstOrNull() !== ticket) return false
        waiting.removeAt(0)
        running++
        return true
    }
}

// The items of [ids] that [movable] lets through take the places those items hold, in the order of [ids]; the rest
// keep theirs. The one reorder rule, for the start queue and for the task list Dart reads the order from.
internal fun <T> MutableList<T>.swapSlots(ids: List<String>, idOf: (T) -> String, movable: (T) -> Boolean = { true }) {
    val rank = ids.withIndex().associate { (index, id) -> id to index }
    val slots = indices.filter { idOf(this[it]) in rank && movable(this[it]) }
    val moved = slots.map { this[it] }.sortedBy { rank.getValue(idOf(it)) }
    slots.zip(moved).forEach { (slot, item) -> this[slot] = item }
}
