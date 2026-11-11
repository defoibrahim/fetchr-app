package com.defo.fetchr

import com.defo.fetchr.pigeon.FetchrError
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import org.junit.Assert.assertEquals
import org.junit.Test

class ErrorClassifierTest {
    private fun classify(message: String?) = ErrorClassifier.classify(RuntimeException(message))

    @Test
    fun diskFullIsNoStorage() {
        val (code, message) = classify("ERROR: unable to write data: [Errno 28] No space left on device")
        assertEquals("no_storage", code)
        assertEquals("unable to write data: [Errno 28] No space left on device", message)
    }

    @Test
    fun securityExceptionIsNoStorageWithFriendlyMessage() {
        val (code, message) = ErrorClassifier.classify(SecurityException("denied"))
        assertEquals("no_storage", code)
        assertEquals("Couldn't save the file. Free up space or allow storage access, then retry.", message)
    }

    @Test
    fun enospcIsNoStorage() {
        assertEquals("no_storage", classify("ERROR: write failed (ENOSPC)").first)
    }

    @Test
    fun urlopenErrorIsNetwork() {
        val (code, message) = classify(
            "ERROR: [generic] Unable to download webpage: <urlopen error [Errno 111] Connection refused>",
        )
        assertEquals("network", code)
        assertEquals(
            "[generic] Unable to download webpage: <urlopen error [Errno 111] Connection refused>",
            message,
        )
    }

    @Test
    fun nameResolutionFailureIsNetwork() {
        assertEquals(
            "network",
            classify("ERROR: unable to download video data: Temporary failure in name resolution").first,
        )
    }

    @Test
    fun timeoutAndResetAndUnreachableAreNetwork() {
        assertEquals("network", classify("ERROR: read timed out").first)
        assertEquals("network", classify("ERROR: Connection reset by peer").first)
        assertEquals("network", classify("ERROR: [Errno 101] Network is unreachable").first)
        assertEquals("network", classify("ERROR: [Errno 110] Connection timed out").first)
    }

    @Test
    fun errnoMatchesWholeNumberOnly() {
        assertEquals("unknown", classify("ERROR: [Errno 1101] something odd").first)
    }

    @Test
    fun networkExceptionTypesAreNetworkWithFriendlyMessage() {
        val expected = "No internet connection. Check your connection and try again."
        assertEquals("network" to expected, ErrorClassifier.classify(UnknownHostException("youtube.com")))
        assertEquals("network" to expected, ErrorClassifier.classify(SocketTimeoutException("timeout")))
    }

    @Test
    fun wrappedNetworkExceptionIsFoundInCauseChain() {
        val wrapped = RuntimeException("failed", UnknownHostException("youtube.com"))
        assertEquals("network", ErrorClassifier.classify(wrapped).first)
    }

    @Test
    fun unsupportedUrl() {
        val (code, message) = classify("ERROR: Unsupported URL: https://example.com/foo")
        assertEquals("unsupported_site", code)
        assertEquals("Unsupported URL: https://example.com/foo", message)
    }

    @Test
    fun privateVideoVariants() {
        assertEquals(
            "private_video",
            classify("ERROR: [youtube] abc: Private video. Sign in if you've been granted access").first,
        )
        assertEquals(
            "private_video",
            classify("ERROR: [youtube] abc: Sign in to confirm your age").first,
        )
        assertEquals(
            "private_video",
            classify("ERROR: [youtube] abc: This video is members-only content").first,
        )
        assertEquals(
            "private_video",
            classify("ERROR: [youtube] abc: Join this channel to get access to members-only content").first,
        )
    }

    @Test
    fun unavailableVariants() {
        val (code, message) = classify("ERROR: [youtube] abc: Video unavailable")
        assertEquals("unavailable", code)
        assertEquals("[youtube] abc: Video unavailable", message)
        assertEquals("unavailable", classify("ERROR: [youtube] abc: This video is unavailable").first)
        assertEquals("unavailable", classify("ERROR: [vimeo] 1: This video has been removed").first)
        assertEquals(
            "unavailable",
            classify("ERROR: [youtube] abc: The uploader has not made this video available in your country").first,
        )
        assertEquals(
            "unavailable",
            classify("ERROR: [youtube] abc: This video is not available in your country").first,
        )
        assertEquals("unavailable", classify("ERROR: Unable to download: HTTP Error 404: Not Found").first)
    }

    @Test
    fun unknownPassesLastErrorLineThrough() {
        val (code, message) = classify(
            "WARNING: first\nERROR: first failure\nWARNING: retrying\nERROR: something odd happened\n",
        )
        assertEquals("unknown", code)
        assertEquals("something odd happened", message)
    }

    @Test
    fun unknownWithoutErrorLineUsesLastNonBlankLine() {
        val (code, message) = classify("Traceback\n  boom\nValueError: bad thing\n\n")
        assertEquals("unknown", code)
        assertEquals("ValueError: bad thing", message)
    }

    @Test
    fun unknownWithoutMessageIsFriendly() {
        val (code, message) = classify(null)
        assertEquals("unknown", code)
        assertEquals("Something went wrong. If it keeps happening, update yt-dlp in Settings.", message)
    }

    @Test
    fun checksRunInContractOrder() {
        assertEquals(
            "no_storage",
            classify("ERROR: urlopen error: [Errno 28] No space left on device").first,
        )
        assertEquals(
            "network",
            classify("ERROR: urlopen error while fetching Unsupported URL page").first,
        )
        assertEquals(
            "unsupported_site",
            classify("ERROR: Unsupported URL: https://example.com/private video").first,
        )
        assertEquals(
            "private_video",
            classify("ERROR: Private video, Video unavailable").first,
        )
    }

    @Test
    fun warningsAreIgnoredWhenAnErrorLineExists() {
        val (code, _) = classify(
            "WARNING: Unable to download webpage: timed out. Retrying\nERROR: [youtube] abc: Video unavailable",
        )
        assertEquals("unavailable", code)
    }

    @Test
    fun permissionDeniedErrnoIsPermissionDenied() {
        val (code, message) = classify("ERROR: [Errno 13] Permission denied: '/storage/emulated/0/Movies/Fetchr'")
        assertEquals("permission_denied", code)
        assertEquals("[Errno 13] Permission denied: '/storage/emulated/0/Movies/Fetchr'", message)
    }

    @Test
    fun eaccesIsPermissionDenied() {
        assertEquals("permission_denied", classify("ERROR: unable to open for writing: EACCES").first)
        assertEquals("permission_denied", classify("open failed: EACCES (Permission denied)").first)
    }

    @Test
    fun permissionDeniedHasAFriendlyFallbackMessage() {
        val (code, message) = classify("Permission denied")
        assertEquals("permission_denied", code)
        assertEquals("Fetchr can't save files. Allow storage access in the app settings, then retry.", message)
    }

    @Test
    fun aCodedPermissionErrorPassesThrough() {
        val error = FetchrError("permission_denied", ErrorClassifier.PERMISSION_DENIED_MESSAGE, null)
        assertEquals("permission_denied" to ErrorClassifier.PERMISSION_DENIED_MESSAGE, ErrorClassifier.classify(error))
    }

    @Test
    fun noSpaceAndNetworkStillWinOverPermissionDenied() {
        assertEquals("no_storage", classify("ERROR: [Errno 28] No space left on device, Permission denied").first)
        assertEquals("network", classify("ERROR: <urlopen error [Errno 13] Permission denied>").first)
    }

    @Test
    fun fetchrErrorKeepsItsCode() {
        val (code, message) = ErrorClassifier.classify(FetchrError("invalid_url", "Not a web link", null))
        assertEquals("invalid_url", code)
        assertEquals("Not a web link", message)
    }
}
