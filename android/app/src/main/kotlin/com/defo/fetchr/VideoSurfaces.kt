package com.defo.fetchr

import android.util.Log
import com.alexmercerind.media_kit_video.MediaKitVideoPlugin
import com.alexmercerind.media_kit_video.VideoOutputManager
import io.flutter.embedding.engine.FlutterEngine

// media_kit_video 2.0.1 keeps its SurfaceProducers when the engine detaches, and Flutter 3.47 schedules an engine
// frame for every image they still receive. When the Activity goes while DownloadService keeps the process alive,
// libmpv keeps drawing and the next frame throws "FlutterJNI is not attached to native" on the main thread.
// Releasing the producers first makes the engine drop those images. Flutter fixed it in 3.49 (flutter/flutter#191204);
// drop this then. The field names are kept from R8 in proguard-rules.pro.
object VideoSurfaces {
    private const val TAG = "VideoSurfaces"

    fun release(engine: FlutterEngine) {
        val plugin = engine.plugins.get(MediaKitVideoPlugin::class.java) as? MediaKitVideoPlugin ?: return
        try {
            val manager = MediaKitVideoPlugin::class.java.getDeclaredField("videoOutputManager")
                .apply { isAccessible = true }
                .get(plugin) as? VideoOutputManager ?: return
            val outputs = VideoOutputManager::class.java.getDeclaredField("videoOutputs")
                .apply { isAccessible = true }
                .get(manager) as? Map<*, *> ?: return
            // dispose removes from the map, so iterate a copy. Main thread, the same one media_kit disposes on.
            outputs.keys.filterIsInstance<Long>().toList().forEach(manager::dispose)
        } catch (e: ReflectiveOperationException) {
            Log.w(TAG, "Could not release the video surfaces", e)
        }
    }
}
