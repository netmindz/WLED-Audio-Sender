package net.netmindz.wled.sender

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "net.netmindz.wled.sender/audio_capture"
        private const val EVENT_CHANNEL = "net.netmindz.wled.sender/audio_stream"
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var methodResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingSampleRate: Int = 22050

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startCapture" -> {
                    pendingSampleRate = call.argument<Int>("sampleRate") ?: 22050
                    requestMediaProjection(result)
                }
                "stopCapture" -> {
                    stopCapture()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Re-attach callback if service is already running (e.g. after activity recreation)
                    if (AudioCaptureForegroundService.isRunning) {
                        AudioCaptureForegroundService.onAudioData = { pcmData ->
                            runOnUiThread {
                                eventSink?.success(pcmData)
                            }
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun requestMediaProjection(result: MethodChannel.Result) {
        methodResult = result
        val projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(projectionManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Set up the callback before starting the service
                AudioCaptureForegroundService.onAudioData = { pcmData ->
                    runOnUiThread {
                        eventSink?.success(pcmData)
                    }
                }

                // Start the foreground service — it will create MediaProjection
                // AFTER startForeground() is called (required on Android 14+)
                val serviceIntent = Intent(this, AudioCaptureForegroundService::class.java).apply {
                    putExtra("resultCode", resultCode)
                    putExtra("data", data)
                    putExtra("sampleRate", pendingSampleRate)
                }
                startForegroundService(serviceIntent)

                methodResult?.success(true)
            } else {
                methodResult?.error("PERMISSION_DENIED", "User denied screen capture permission", null)
            }
            methodResult = null
        }
    }

    private fun stopCapture() {
        AudioCaptureForegroundService.onAudioData = null
        val serviceIntent = Intent(this, AudioCaptureForegroundService::class.java)
        stopService(serviceIntent)
    }

    // Do NOT stop capture on activity destroy — the foreground service should
    // keep running. Capture only stops when the user explicitly taps stop.
}
