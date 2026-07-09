package cc.aiixi.media_control

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.Manifest
import android.graphics.Bitmap
import android.graphics.Bitmap.CompressFormat
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.provider.Settings
import android.util.Base64
import java.io.ByteArrayOutputStream
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "media_control/media"
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getMediaSnapshot" -> result.success(buildSnapshot())
                    "play" -> {
                        sendTransportControl(call.argument<String>("packageName"), TransportAction.PLAY)
                        result.success(null)
                    }
                    "pause" -> {
                        sendTransportControl(call.argument<String>("packageName"), TransportAction.PAUSE)
                        result.success(null)
                    }
                    "next" -> {
                        sendTransportControl(call.argument<String>("packageName"), TransportAction.NEXT)
                        result.success(null)
                    }
                    "previous" -> {
                        sendTransportControl(call.argument<String>("packageName"), TransportAction.PREVIOUS)
                        result.success(null)
                    }
                    "seekTo" -> {
                        val positionMs = (call.argument<Number>("positionMs")?.toLong() ?: 0L).coerceAtLeast(0L)
                        sendTransportControl(call.argument<String>("packageName"), TransportAction.SEEK_TO, positionMs)
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "ensureNotificationPermission" -> {
                        ensureNotificationPermission(result)
                    }
                    "startBackgroundProtection" -> {
                        startBackgroundProtectionService(call.argument<String>("webUrl"))
                        result.success(null)
                    }
                    "updateBackgroundProtectionNotification" -> {
                        startBackgroundProtectionService(call.argument<String>("webUrl"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("media_control_error", error.message, null)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) {
            return
        }

        val result = pendingNotificationPermissionResult ?: return
        pendingNotificationPermissionResult = null

        val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        result.success(granted)
    }

    private fun buildSnapshot(): Map<String, Any?> {
        val controllers = getActiveControllers()
        val listenerEnabled = NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)

        return mapOf(
            "listenerEnabled" to listenerEnabled,
            "timestampMs" to System.currentTimeMillis(),
            "sessions" to controllers.map { controller -> controller.toMap() },
        )
    }

    private fun getActiveControllers(): List<MediaController> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return emptyList()
        }

        val sessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        val listenerComponent = ComponentName(this, MediaNotificationListenerService::class.java)
        return try {
            sessionManager.getActiveSessions(listenerComponent)
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    private fun sendTransportControl(packageName: String?, action: TransportAction, positionMs: Long = 0L) {
        val controller = findController(packageName) ?: return
        when (action) {
            TransportAction.PLAY -> controller.transportControls.play()
            TransportAction.PAUSE -> controller.transportControls.pause()
            TransportAction.NEXT -> controller.transportControls.skipToNext()
            TransportAction.PREVIOUS -> controller.transportControls.skipToPrevious()
            TransportAction.SEEK_TO -> controller.transportControls.seekTo(positionMs)
        }
    }

    private fun findController(packageName: String?): MediaController? {
        val controllers = getActiveControllers()
        if (controllers.isEmpty()) {
            return null
        }

        if (packageName != null) {
            controllers.firstOrNull { it.packageName == packageName }?.let { return it }
        }

        return controllers.first()
    }

    private fun openNotificationSettings() {
        startActivity(
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }

        if (pendingNotificationPermissionResult != null) {
            result.error("permission_request_in_progress", "Notification permission request is already in progress.", null)
            return
        }

        pendingNotificationPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
    }

    private fun startBackgroundProtectionService(webUrl: String? = null) {
        val serviceIntent = Intent(this, MediaProtectionService::class.java).apply {
            if (webUrl != null) {
                putExtra(MediaProtectionService.EXTRA_WEB_URL, webUrl)
            }
        }
        ContextCompat.startForegroundService(this, serviceIntent)
    }

    private fun MediaController.toMap(): Map<String, Any?> {
        val metadata = this.metadata
        val state = this.playbackState
        val actions = state?.actions ?: 0L
        val durationMs = metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION)?.coerceAtLeast(0L) ?: 0L
        val positionMs = state?.position?.coerceAtLeast(0L) ?: 0L

        return mapOf(
            "packageName" to packageName,
            "appName" to resolveAppName(packageName),
            "title" to (metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "Unknown title"),
            "artist" to (metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""),
            "album" to (metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""),
            "artworkDataUrl" to extractArtworkDataUrl(metadata),
            "durationMs" to durationMs,
            "positionMs" to positionMs,
            "playbackState" to playbackStateLabel(state?.state),
            "isPlaying" to (state?.state == PlaybackState.STATE_PLAYING),
            "canPlay" to actionsHas(actions, PlaybackState.ACTION_PLAY),
            "canPause" to actionsHas(actions, PlaybackState.ACTION_PAUSE),
            "canSkipNext" to actionsHas(actions, PlaybackState.ACTION_SKIP_TO_NEXT),
            "canSkipPrevious" to actionsHas(actions, PlaybackState.ACTION_SKIP_TO_PREVIOUS),
            "canSeekTo" to actionsHas(actions, PlaybackState.ACTION_SEEK_TO),
        )
    }

    private fun resolveAppName(packageName: String): String {
        return try {
            val applicationInfo: ApplicationInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(applicationInfo).toString()
        } catch (_: Exception) {
            packageName
        }
    }

    private fun extractArtworkDataUrl(metadata: MediaMetadata?): String? {
        if (metadata == null) {
            return null
        }

        val bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
            ?: return null

        return bitmapToDataUrl(bitmap)
    }

    private fun bitmapToDataUrl(bitmap: Bitmap): String {
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(CompressFormat.PNG, 100, outputStream)
        val base64 = Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
        return "data:image/png;base64,$base64"
    }

    private fun playbackStateLabel(state: Int?): String {
        return when (state) {
            PlaybackState.STATE_BUFFERING -> "buffering"
            PlaybackState.STATE_CONNECTING -> "connecting"
            PlaybackState.STATE_ERROR -> "error"
            PlaybackState.STATE_FAST_FORWARDING -> "fast_forwarding"
            PlaybackState.STATE_NONE -> "none"
            PlaybackState.STATE_PAUSED -> "paused"
            PlaybackState.STATE_PLAYING -> "playing"
            PlaybackState.STATE_REWINDING -> "rewinding"
            PlaybackState.STATE_SKIPPING_TO_NEXT -> "skipping_next"
            PlaybackState.STATE_SKIPPING_TO_PREVIOUS -> "skipping_previous"
            PlaybackState.STATE_STOPPED -> "stopped"
            else -> "unknown"
        }
    }

    private fun actionsHas(actions: Long, action: Long): Boolean {
        return actions and action != 0L
    }

    private enum class TransportAction {
        PLAY,
        PAUSE,
        NEXT,
        PREVIOUS,
        SEEK_TO,
    }

    companion object {
        private const val REQUEST_NOTIFICATION_PERMISSION = 1001
    }
}
