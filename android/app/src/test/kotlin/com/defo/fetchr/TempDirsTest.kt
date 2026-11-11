package com.defo.fetchr

import com.defo.fetchr.TaskFixtures.task
import com.defo.fetchr.pigeon.TaskStatus
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TempDirsTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun keepsDirsOfPausedAndFailedTasks() {
        val tasks = listOf(
            task(id = "paused", status = TaskStatus.PAUSED),
            task(id = "failed", status = TaskStatus.FAILED),
        )
        assertEquals(emptyList<String>(), TempDirs.orphans(listOf("paused", "failed"), tasks))
    }

    @Test fun deletesDirsOfEveryOtherStatusAndUnknownIds() {
        val tasks = listOf(
            task(id = "done", status = TaskStatus.COMPLETED),
            task(id = "canceled", status = TaskStatus.CANCELED),
            task(id = "queued", status = TaskStatus.QUEUED),
            task(id = "kept", status = TaskStatus.PAUSED),
        )
        assertEquals(
            listOf("done", "canceled", "queued", "gone"),
            TempDirs.orphans(listOf("done", "canceled", "queued", "kept", "gone"), tasks),
        )
    }

    @Test fun noDirsMeansNothingToDelete() {
        assertEquals(emptyList<String>(), TempDirs.orphans(emptyList(), listOf(task())))
    }

    @Test fun cookieFileOlderThanTheProcessIsStale() {
        assertTrue(TempDirs.isStaleCookieFile("tmpab12cd.cookies", lastModifiedMs = 99, processStartMs = 100))
    }

    @Test fun cookieFileFromThisProcessIsKept() {
        assertFalse(TempDirs.isStaleCookieFile("tmpab12cd.cookies", lastModifiedMs = 100, processStartMs = 100))
        assertFalse(TempDirs.isStaleCookieFile("tmpab12cd.cookies", lastModifiedMs = 101, processStartMs = 100))
    }

    @Test fun onlyTmpCookieFilesCanBeStale() {
        for (name in listOf("tmpab12cd.txt", "ab12cd.cookies", "cookies", "tmp", "yt-dlp", "downloads")) {
            assertFalse(name, TempDirs.isStaleCookieFile(name, lastModifiedMs = 0, processStartMs = 100))
        }
    }

    @Test fun deletesOnlyStaleCookieFilesDirectlyInTheCacheDir() {
        val cache = tmp.newFolder("cache")
        fun file(parent: File, name: String, modifiedMs: Long) =
            File(parent, name).apply { writeText("x"); setLastModified(modifiedMs) }
        val stale = file(cache, "tmpold.cookies", 1_000)
        val fresh = file(cache, "tmpnew.cookies", 9_000)
        val other = file(cache, "tmpold.txt", 1_000)
        val nested = file(File(cache, "downloads").apply { mkdirs() }, "tmpold.cookies", 1_000)

        TempDirs.deleteStaleCookieFiles(cache, processStartMs = 5_000)

        assertFalse(stale.exists())
        assertTrue(fresh.exists())
        assertTrue(other.exists())
        assertTrue(nested.exists())
    }
}
