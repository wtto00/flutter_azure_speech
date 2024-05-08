package wang.tato.azure_speech

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import com.microsoft.cognitiveservices.speech.audio.PullAudioInputStreamCallback
import kotlin.math.log10

class MicrophoneStream(val onVolumeChange: ((Double) -> Unit)? = null) : PullAudioInputStreamCallback() {

    private val sampleRate: Int = 16000
    private val format: AudioFormat = AudioFormat.Builder().setSampleRate(sampleRate)
        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
        .build()
    private val bufferSize: Int = AudioRecord.getMinBufferSize(
        format.sampleRate, format.channelMask, format.encoding
    )
    private var recorder: AudioRecord? = null

    init {
        initMic()
    }

    @SuppressLint("MissingPermission")
    fun initMic() {
        // Note: currently, the Speech SDK support 16 kHz sample rate, 16 bit samples, mono (single-channel) only.
        recorder = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(format).build()

        recorder!!.startRecording()
    }

    override fun read(dataBuffer: ByteArray?): Int {
        if (recorder != null && dataBuffer != null) {
            val ret: Long = recorder!!.read(dataBuffer, 0, dataBuffer.size).toLong()

            val buffer = ShortArray(bufferSize)
            val r: Int = recorder!!.read(buffer, 0, bufferSize)
            var v: Long = 0
            for (i in buffer.indices) {
                v += buffer[i] * buffer[i]
            }
            val mean = v / r.toDouble()
            val volume = 10 * log10(mean)
            onVolumeChange?.let { it(volume) }

            return ret.toInt()
        }
        return 0
    }

    override fun close() {
        if (recorder != null) {
            recorder!!.release()
            recorder = null
        }
    }
}