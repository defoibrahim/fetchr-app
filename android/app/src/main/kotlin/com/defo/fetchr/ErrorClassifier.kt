package com.defo.fetchr

import com.defo.fetchr.pigeon.FetchrError
import java.net.SocketTimeoutException
import java.net.UnknownHostException

object ErrorClassifier {
    private class Rule(
        val code: String,
        val text: Regex,
        val fallback: String,
        val types: List<Class<out Throwable>> = emptyList(),
    )

    private const val UNKNOWN_MESSAGE = "Something went wrong. If it keeps happening, update yt-dlp in Settings."
    const val PERMISSION_DENIED_MESSAGE = "Fetchr can't save files. Allow storage access in the app settings, then retry."

    // Order matters: the first rule that matches wins.
    private val rules = listOf(
        Rule(
            "no_storage",
            Regex("""\bErrno 28\b|No space left|ENOSPC""", RegexOption.IGNORE_CASE),
            "Couldn't save the file. Free up space or allow storage access, then retry.",
            listOf(SecurityException::class.java),
        ),
        Rule(
            "network",
            Regex(
                """urlopen error|\bErrno (?:7|101|110|111)\b|timed out|Temporary failure in name resolution|Network is unreachable|Connection reset""",
                RegexOption.IGNORE_CASE,
            ),
            "No internet connection. Check your connection and try again.",
            listOf(UnknownHostException::class.java, SocketTimeoutException::class.java),
        ),
        // After network: a blocked socket also reports Errno 13, inside a urlopen error.
        Rule(
            "permission_denied",
            Regex("""\bErrno 13\b|\bEACCES\b|Permission denied""", RegexOption.IGNORE_CASE),
            PERMISSION_DENIED_MESSAGE,
        ),
        Rule(
            "unsupported_site",
            Regex("""Unsupported URL""", RegexOption.IGNORE_CASE),
            "This site isn't supported.",
        ),
        Rule(
            "private_video",
            Regex("""Private video|Sign in to confirm|members-only|Join this channel""", RegexOption.IGNORE_CASE),
            "This video is private or needs a sign-in.",
        ),
        Rule(
            "unavailable",
            Regex(
                """Video unavailable|This video is unavailable|has been removed|(?:not|made this video) available in your country|HTTP Error 404""",
                RegexOption.IGNORE_CASE,
            ),
            "This video isn't available. It may have been removed or blocked in your region.",
        ),
    )

    fun classify(t: Throwable): Pair<String, String> {
        if (t is FetchrError) return t.code to (t.message ?: UNKNOWN_MESSAGE)

        val raw = t.message.orEmpty()
        val lines = raw.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val errorLine = lines
            .lastOrNull { it.startsWith("ERROR:") }
            ?.removePrefix("ERROR:")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        // Retry warnings earlier in stderr mention timeouts even when the final error is something else.
        val text = errorLine ?: raw
        val chain = generateSequence(t) { it.cause }.take(8).toList()

        val rule = rules.firstOrNull { r ->
            r.text.containsMatchIn(text) || chain.any { c -> r.types.any { it.isInstance(c) } }
        }
        val message = errorLine ?: rule?.fallback ?: lines.lastOrNull() ?: UNKNOWN_MESSAGE
        return (rule?.code ?: "unknown") to message
    }
}
