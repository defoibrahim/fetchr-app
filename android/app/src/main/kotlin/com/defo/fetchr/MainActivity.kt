package com.defo.fetchr

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.os.Bundle
import android.window.SplashScreenView
import androidx.annotation.RequiresApi
import com.defo.fetchr.pigeon.DownloadsStreamHandler
import com.defo.fetchr.pigeon.FetchrApiPigeonMethodCodec
import com.defo.fetchr.pigeon.FetchrHostApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CompletableDeferred
import java.time.Instant

private const val REQUEST_INTENT_SENDER = 0xFE7C
private const val REQUEST_RESULT = 0xFE7D
private const val DOWNLOADS_CHANNEL = "dev.flutter.pigeon.grabby.FetchrEvents.downloads"

class MainActivity : FlutterActivity() {
    private val downloadsStream = DownloadsStream()
    private var pendingSender: CompletableDeferred<Boolean>? = null
    private var pendingResult: CompletableDeferred<Intent?>? = null
    private val splashGone = CompletableDeferred<Unit>()

    // Registered before super.onCreate: the platform reads it during onResume. Android 12+ otherwise plays its own
    // fade over Flutter's first frame, which already draws the splash tile where the icon sits.
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener(::holdThenRemove)
        } else {
            // The system removes the static splash by itself when Flutter draws.
            splashGone.complete(Unit)
        }
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        splashGone.complete(Unit)
        super.onDestroy()
    }

    // Never completes when the system hands over no copyable splash (a solid-colour one on 12 and 12L), so Dart bounds the wait.
    suspend fun awaitLaunchSplash() = splashGone.await()

    // The listener only fires after Flutter's first frame, so waiting out the icon animation is all that is left.
    @RequiresApi(Build.VERSION_CODES.S)
    private fun holdThenRemove(view: SplashScreenView) {
        val wait = if (view.iconView == null) {
            0L
        } else {
            SplashHold.remainingMs(view.iconAnimationStart, view.iconAnimationDuration, Instant.now())
        }
        val remove = {
            try {
                view.remove()
                // remove() resets the system bar colours to what they were before Dart ran.
                updateSystemUiOverlays()
            } finally {
                splashGone.complete(Unit)
            }
        }
        if (wait == 0L) remove() else view.postDelayed(remove, wait)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        FetchrHostApi.setUp(messenger, HostApi(this))
        DownloadsStreamHandler.register(messenger, downloadsStream)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        FetchrHostApi.setUp(messenger, null)
        // The generated code has no unregister, and removing the handler does not call onCancel.
        EventChannel(messenger, DOWNLOADS_CHANNEL, FetchrApiPigeonMethodCodec).setStreamHandler(null)
        downloadsStream.onCancel(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Call from the main thread.
    suspend fun launchIntentSender(sender: IntentSender): Boolean {
        val result = CompletableDeferred<Boolean>()
        pendingSender?.complete(false)
        pendingSender = result
        try {
            startIntentSenderForResult(sender, REQUEST_INTENT_SENDER, null, 0, 0, 0)
        } catch (e: IntentSender.SendIntentException) {
            pendingSender = null
            throw e
        }
        return result.await()
    }

    // Call from the main thread. The result's intent, or null when the user backs out.
    suspend fun launchForResult(intent: Intent): Intent? {
        val result = CompletableDeferred<Intent?>()
        pendingResult?.complete(null)
        pendingResult = result
        try {
            startActivityForResult(intent, REQUEST_RESULT)
        } catch (e: ActivityNotFoundException) {
            pendingResult = null
            throw e
        }
        return result.await()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_INTENT_SENDER) {
            pendingSender?.complete(resultCode == Activity.RESULT_OK)
            pendingSender = null
        } else if (requestCode == REQUEST_RESULT) {
            pendingResult?.complete(data.takeIf { resultCode == Activity.RESULT_OK })
            pendingResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
