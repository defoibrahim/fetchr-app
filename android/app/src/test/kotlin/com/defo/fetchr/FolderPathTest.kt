package com.defo.fetchr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FolderPathTest {
    private val root = "/storage/emulated/0"

    @Test
    fun relativePathDropsTheTrailingSlash() {
        assertEquals("primary:Movies/Fetchr", FolderPath.fromRelativePath("Movies/Fetchr/"))
    }

    @Test
    fun relativePathKeepsNestedFolders() {
        assertEquals("primary:Music/Fetchr/Mixes", FolderPath.fromRelativePath("Music/Fetchr/Mixes/"))
    }

    @Test
    fun missingOrEmptyRelativePathHasNoFolder() {
        assertNull(FolderPath.fromRelativePath(null))
        assertNull(FolderPath.fromRelativePath(""))
    }

    @Test
    fun legacyDataPathGivesTheParentFolder() {
        assertEquals(
            "primary:Movies/Fetchr",
            FolderPath.fromDataPath("$root/Movies/Fetchr/clip.mp4", root),
        )
        assertEquals(
            "primary:Pictures/Fetchr/Covers",
            FolderPath.fromDataPath("$root/Pictures/Fetchr/Covers/a.jpg", "$root/"),
        )
    }

    @Test
    fun dataPathGivesTheRelativePathShape() {
        assertEquals("Movies/Fetchr/", FolderPath.relativeOfData("$root/Movies/Fetchr/clip.mp4", root))
        assertEquals(
            "Pictures/Fetchr/Covers/",
            FolderPath.relativeOfData("$root/Pictures/Fetchr/Covers/a.jpg", "$root/"),
        )
    }

    @Test
    fun dataPathOutsideTheExternalRootHasNoRelativePath() {
        assertNull(FolderPath.relativeOfData("/storage/ABCD-1234/Movies/Fetchr/clip.mp4", root))
        assertNull(FolderPath.relativeOfData("$root/clip.mp4", root))
        assertNull(FolderPath.relativeOfData(null, root))
    }

    @Test
    fun pathOutsideTheExternalRootHasNoFolder() {
        assertNull(FolderPath.fromDataPath("/storage/ABCD-1234/Movies/Fetchr/clip.mp4", root))
        // A sibling that merely shares the prefix is not inside the root.
        assertNull(FolderPath.fromDataPath("/storage/emulated/01/Movies/clip.mp4", root))
        assertNull(FolderPath.fromDataPath("$root/clip.mp4", root))
        assertNull(FolderPath.fromDataPath(null, root))
    }
}
