package com.defo.fetchr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

// The large icon of a result notification, from the request's thumbnail url.
internal object NotificationThumbnail {
    private const val TAG = "NotificationThumbnail"
    private const val TIMEOUT_MS = 3_000
    const val MAX_PX = 256
    private const val MAX_BYTES = 2 * 1024 * 1024

    // The request's thumbnail url, fetched within TIMEOUT_MS and decoded to at most MAX_PX; null on any
    // failure, because a notification without a picture beats none.
    // ponytail: a socket read cannot be interrupted, so a stalled server can overrun the deadline by one read timeout.
    fun fetch(url: String?): Bitmap? {
        if (url.isNullOrEmpty()) return null
        return try {
            val connection = URL(url).openConnection() as? HttpURLConnection ?: return null
            try {
                connection.connectTimeout = TIMEOUT_MS
                connection.readTimeout = TIMEOUT_MS
                val bytes = readBounded(connection) ?: return null
                decode(bytes)
            } finally {
                connection.disconnect()
            }
        } catch (e: IOException) {
            Log.d(TAG, "No notification thumbnail", e)
            null
        } catch (e: RuntimeException) {
            Log.d(TAG, "No notification thumbnail", e)
            null
        }
    }

    private fun readBounded(connection: HttpURLConnection): ByteArray? {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(TIMEOUT_MS.toLong())
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        connection.inputStream.use { input ->
            while (true) {
                if (System.nanoTime() > deadline || out.size() > MAX_BYTES) return null
                val read = input.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
            }
        }
        return out.toByteArray()
    }

    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > MAX_PX) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }
}
