package com.defo.fetchr

import android.util.Log
import java.util.concurrent.ConcurrentHashMap

// media_kit gives each libmpv player a Dart wakeup callback and removes it only when Dart disposes the player. If
// Android destroys MainActivity with a player open while DownloadService keeps the process alive, the engine and that
// callback go first, and mpv's next event aborts the process ("Callback invoked after it has been deleted"). Before
// the engine goes, MainActivity detaches every tracked player: its wakeup callback is cleared and it quits, which also
// stops its audio.
object MpvGuard {
    private const val TAG = "MpvGuard"

    internal val players = PlayerHandles(
        detach = { handles ->
            try {
                MpvNative.detach(handles)
            } catch (e: LinkageError) {
                Log.w(TAG, "Could not detach ${handles.size} players", e)
            }
        },
        clearWakeup = { handle ->
            try {
                MpvNative.clearWakeup(handle)
            } catch (e: LinkageError) {
                Log.w(TAG, "Could not clear a player's wakeup callback", e)
            }
        },
    )
}

internal class PlayerHandles(
    private val detach: (LongArray) -> Unit,
    private val clearWakeup: (Long) -> Unit,
) {
    private val handles: MutableSet<Long> = ConcurrentHashMap.newKeySet()

    fun track(handle: Long) {
        if (handle != 0L) handles += handle
    }

    // Called from the player's dispose while libmpv still owns the handle (it is freed seconds later).
    fun untrack(handle: Long) {
        if (handle == 0L) return
        handles -= handle
        clearWakeup(handle)
    }

    fun detachAll() {
        val open = handles.toLongArray()
        handles.clear()
        if (open.isNotEmpty()) detach(open)
    }
}

private object MpvNative {
    init {
        System.loadLibrary("fetchr_mpv")
    }

    @JvmStatic
    external fun detach(handles: LongArray)

    @JvmStatic
    external fun clearWakeup(handle: Long)
}
