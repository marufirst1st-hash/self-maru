package com.floormeasure.floor_measure

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 네이티브 오디오 녹음 (Sonar Worker용)
 * FMCW chirp 재생 후 에코 녹음 → Flutter로 전달
 */
class SonarRecorder(
    private val engine: FlutterEngine,
    private val activity: android.app.Activity,
) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.floormeasure/sonar")
    private var recorder: AudioRecord? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "record" -> {
                    val durationMs = call.argument<Int>("durationMs") ?: 100
                    val data = record(durationMs)
                    result.success(data)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun record(durationMs: Int): List<Double>? {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            return null
        }

        try {
            val sampleRate = 48000
            val bufferSize = (sampleRate * durationMs / 1000)
            val minBuf = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            recorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                Math.max(bufferSize * 2, minBuf)
            )

            val buffer = ShortArray(bufferSize)
            recorder!!.startRecording()
            val read = recorder!!.read(buffer, 0, bufferSize)
            recorder!!.stop()
            recorder!!.release()
            recorder = null

            if (read <= 0) return null

            // Short → Double (정규화 -1~1)
            return buffer.take(read).map { it.toDouble() / 32768.0 }
        } catch (e: Exception) {
            recorder?.release()
            recorder = null
            return null
        }
    }

    fun dispose() {
        recorder?.release()
        recorder = null
    }
}
