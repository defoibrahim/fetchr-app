package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadTask
import java.io.File

internal object TempDirs {
    // Dir names under cache/<TEMP_DIR> that no paused or failed task owns.
    fun orphans(dirNames: List<String>, tasks: List<DownloadTask>): List<String> {
        val kept = tasks.filter { TaskTransitions.keepsPartialFiles(it.status) }.mapTo(HashSet()) { it.id }
        return dirNames.filterNot { it in kept }
    }

    // yt-dlp's aria2c downloader writes cache/tmp*.cookies and deletes it in a finally that a kill on pause or cancel
    // skips. One older than this process belongs to a run that is gone.
    fun isStaleCookieFile(name: String, lastModifiedMs: Long, processStartMs: Long): Boolean =
        name.startsWith("tmp") && name.endsWith(".cookies") && lastModifiedMs < processStartMs

    fun deleteStaleCookieFiles(cacheDir: File, processStartMs: Long) {
        cacheDir.listFiles().orEmpty()
            .filter { it.isFile && isStaleCookieFile(it.name, it.lastModified(), processStartMs) }
            .forEach { it.delete() }
    }
}
