package net.netmindz.wled.sender

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager

class AudioCaptureService(
    private val context: Context,
    private val resultCode: Int,
    private val data: Intent,
    private val sampleRate: Int,
    private val onData: (ByteArray) -> Unit
) {
    private var audioRecord: AudioRecord? = null
    private var mediaProjection: MediaProjection? = null
    private var captureThread: Thread? = null
    @Volatile
    private var isCapturing = false

    fun start() {
        val projectionManager = context.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)

        val config = AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val audioFormat = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(sampleRate)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()

        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioRecord = AudioRecord.Builder()
            .setAudioPlaybackCaptureConfig(config)
            .setAudioFormat(audioFormat)
            .setBufferSizeInBytes(bufferSize.coerceAtLeast(1024))
            .build()

        isCapturing = true
        audioRecord?.startRecording()

        captureThread = Thread {
            val buffer = ByteArray(1024) // 512 samples * 2 bytes (16-bit)
            while (isCapturing) {
                val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: -1
                if (bytesRead > 0) {
                    onData(buffer.copyOf(bytesRead))
                }
            }
        }.apply {
            name = "AudioCaptureThread"
            start()
        }
    }

    fun stop() {
        isCapturing = false
        captureThread?.join(1000)
        captureThread = null
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null
        mediaProjection?.stop()
        mediaProjection = null
    }
}
