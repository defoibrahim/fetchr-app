package com.defo.fetchr

import com.defo.fetchr.pigeon.DownloadRequest
import com.defo.fetchr.pigeon.DownloadTask
import com.defo.fetchr.pigeon.Quality
import com.defo.fetchr.pigeon.TaskStage
import com.defo.fetchr.pigeon.TaskStatus
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

object TaskCodec {
    // Enums are stored by name: pigeon's `raw` is the declaration index and would silently remap on a reorder.
    // `stalled` is a live reading of the last progress line, so it is never stored.
    fun encode(tasks: List<DownloadTask>): String =
        JSONArray(tasks.map { encodeTask(it) }).toString()

    fun decode(json: String): List<DownloadTask> {
        val array = try {
            JSONArray(json)
        } catch (e: JSONException) {
            return emptyList()
        }
        return (0 until array.length()).mapNotNull { i ->
            runCatching { decodeTask(array.getJSONObject(i)) }.getOrNull()
        }
    }

    private fun encodeTask(t: DownloadTask) = JSONObject()
        .put("id", t.id)
        .put("request", encodeRequest(t.request))
        .put("status", t.status.name)
        .put("progress", t.progress)
        .put("etaSeconds", t.etaSeconds)
        .put("errorCode", t.errorCode)
        .put("errorMessage", t.errorMessage)
        .put("savedUri", t.savedUri)
        .put("createdAtMs", t.createdAtMs)
        .put("stage", t.stage.name)
        .put("downloadedBytes", t.downloadedBytes)
        .put("totalBytes", t.totalBytes)
        .put("speedBytesPerSec", t.speedBytesPerSec)
        .put("finishedAtMs", t.finishedAtMs)

    private fun encodeRequest(r: DownloadRequest) = JSONObject()
        .put("url", r.url)
        .put("title", r.title)
        .put("thumbnail", r.thumbnail)
        .put("quality", r.quality.name)
        .put("folder", r.folder)
        .put("useAria2c", r.useAria2c)
        .put("uploader", r.uploader)
        .put("durationSeconds", r.durationSeconds)
        .put("playlistTitle", r.playlistTitle)
        .put("playlistIndex", r.playlistIndex)
        .put("playlistCount", r.playlistCount)

    private fun decodeTask(o: JSONObject): DownloadTask {
        val task = DownloadTask(
            id = o.getString("id"),
            request = decodeRequest(o.getJSONObject("request")),
            status = TaskStatus.valueOf(o.getString("status")),
            progress = o.getDouble("progress"),
            etaSeconds = o.getLong("etaSeconds"),
            errorCode = o.str("errorCode"),
            errorMessage = o.str("errorMessage"),
            savedUri = o.str("savedUri"),
            createdAtMs = o.getLong("createdAtMs"),
            stage = o.str("stage")?.let(TaskStage::valueOf) ?: TaskStage.PREPARING,
            downloadedBytes = o.long("downloadedBytes"),
            totalBytes = o.long("totalBytes"),
            speedBytesPerSec = o.long("speedBytesPerSec"),
            stalled = false,
            finishedAtMs = o.long("finishedAtMs"),
        )
        return TaskTransitions.onRestart(task)
    }

    private fun decodeRequest(o: JSONObject) = DownloadRequest(
        url = o.getString("url"),
        title = o.getString("title"),
        thumbnail = o.str("thumbnail"),
        quality = Quality.valueOf(o.getString("quality")),
        folder = o.getString("folder"),
        useAria2c = o.getBoolean("useAria2c"),
        uploader = o.str("uploader"),
        durationSeconds = o.long("durationSeconds"),
        playlistTitle = o.str("playlistTitle"),
        playlistIndex = o.long("playlistIndex"),
        playlistCount = o.long("playlistCount"),
    )
}
