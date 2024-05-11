package wang.tato.azure_speech

import android.os.Handler
import android.os.Looper
import com.microsoft.cognitiveservices.speech.Connection
import com.microsoft.cognitiveservices.speech.SpeechConfig
import com.microsoft.cognitiveservices.speech.SpeechRecognizer
import com.microsoft.cognitiveservices.speech.SpeechSynthesisCancellationDetails
import com.microsoft.cognitiveservices.speech.SpeechSynthesizer
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMethodCodec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch


/** AzureSpeechPlugin */
class AzureSpeechPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    private lateinit var handler: Handler
    private fun invokeMethod(method: String, arguments: Any?) {
        handler.post {
            channel.invokeMethod(method, arguments)
        }
    }

    private fun runInBackground(handler: () -> Unit) {
        CoroutineScope(Dispatchers.IO + SupervisorJob()).launch {
            handler()
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val taskQueue = flutterPluginBinding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "azure_speech",
            StandardMethodCodec.INSTANCE,
            taskQueue
        )
        channel.setMethodCallHandler(this)
        handler = Handler(Looper.getMainLooper())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        closeRecognizer()
        closeSynthesizer()
        closeConfig()
        handler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "buildConfig" -> {
                buildConfig(call, result)
            }

            "startRecognizing" -> {
                startRecognizing(call, result)
            }

            "stopRecognition" -> {
                stopRecognition(result)
            }

            "startSynthesizing" -> {
                startSynthesizing(call, result)
            }

            "stopSynthesize" -> {
                stopSynthesize(result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private var speechConfig: SpeechConfig? = null
    private fun buildSpeechConfig(
        subscriptionKey: String, authorizationToken: String, region: String, result: Result
    ): Boolean {
        if (speechConfig == null) {
            if (region.isEmpty()) {
                result.error("-1", "region cannot be empty", {})
                return false
            }
            if (subscriptionKey.isEmpty() && authorizationToken.isEmpty()) {
                result.error("-2",
                    "subscriptionKey and authorizationToken cannot be empty at the same time",
                    {})
                return false
            }
            speechConfig = if (subscriptionKey.isNotEmpty()) {
                SpeechConfig.fromSubscription(subscriptionKey, region)
            } else {
                SpeechConfig.fromAuthorizationToken(authorizationToken, region)
            }

        } else if (authorizationToken.isNotEmpty()) {
            speechConfig!!.setAuthorizationToken(authorizationToken)
        }
        return true
    }

    private fun closeConfig() {
        if (speechConfig != null) {
            speechConfig!!.close()
            speechConfig = null
        }
    }

    private fun buildConfig(call: MethodCall, result: Result) {
        runInBackground {
            val subscriptionKey: String = call.argument("subscriptionKey") ?: ""
            val authorizationToken: String = call.argument("authorizationToken") ?: ""
            val region: String = call.argument("region") ?: ""
            val success = buildSpeechConfig(subscriptionKey, authorizationToken, region, result)
            if (success) result.success(true)
        }
    }

    private var recognizer: SpeechRecognizer? = null
    private var audioConfig: AudioConfig? = null
    private var microphoneStream: MicrophoneStream? = null
    private fun createRecognizer() {
        microphoneStream = MicrophoneStream(onVolumeChange = { volume: Double ->
            invokeMethod(
                "azure_speech.onVolumeChange", volume
            )
        })
        audioConfig = AudioConfig.fromStreamInput(microphoneStream)
        recognizer = SpeechRecognizer(speechConfig, audioConfig)

        recognizer!!.recognizing.addEventListener { _, speechRecognitionResultEventArgs ->
            val text = speechRecognitionResultEventArgs.result.text
            invokeMethod("azure_speech.onRecognizing", text)
        }
        recognizer!!.recognized.addEventListener { _, speechRecognitionResultEventArgs ->
            val text = speechRecognitionResultEventArgs.result.text
            if (text.isNotEmpty()) invokeMethod("azure_speech.onRecognized", text)
        }
        recognizer!!.canceled.addEventListener { _, speechRecognitionCanceledEventArgs ->
            invokeMethod(
                "azure_speech.onRecognizerCanceled",
                speechRecognitionCanceledEventArgs.errorDetails,
            )
        }
        recognizer!!.sessionStarted.addEventListener { _, _ ->
            invokeMethod("azure_speech.onRecognizerSessionStarted", null)
        }
        recognizer!!.sessionStopped.addEventListener { _, _ ->
            invokeMethod("azure_speech.onRecognizerSessionStopped", null)
        }
        recognizer!!.speechStartDetected.addEventListener { _, _ ->
            invokeMethod("azure_speech.onRecognizerStartDetected", null)
        }
        recognizer!!.speechEndDetected.addEventListener { _, _ ->
            invokeMethod("azure_speech.onRecognizerEndDetected", null)
        }
    }

    private fun closeRecognizer() {
        if (microphoneStream != null) {
            microphoneStream!!.close()
            microphoneStream = null
        }
        if (recognizer != null) {
            recognizer!!.close()
            recognizer = null
        }
        if (audioConfig != null) {
            audioConfig!!.close()
            audioConfig = null
        }
    }

    private fun startRecognizing(call: MethodCall, result: Result) {
        runInBackground {
            try {
                val token: String = call.argument("token") ?: ""
                val language: String = call.argument("language") ?: ""
                val success = buildSpeechConfig("", token, "", result)
                if (!success) return@runInBackground
                if (language.isNotEmpty()) speechConfig!!.setSpeechRecognitionLanguage(language)
                speechConfig!!.requestWordLevelTimestamps()
                if (recognizer != null) {
                    recognizer!!.stopContinuousRecognitionAsync().get()
                    closeRecognizer()
                }
                createRecognizer()
                recognizer!!.startContinuousRecognitionAsync()
                result.success(null)
            } catch (e: Exception) {
                channel.invokeMethod("azure_speech.onException", "Exception: " + e.message)
                result.error("-4", e.message, null)
            }
        }
    }

    private fun stopRecognition(result: Result) {
        runInBackground {
            if (recognizer != null) {
                recognizer!!.stopContinuousRecognitionAsync().get()
            }
            closeRecognizer()
            result.success(null)
        }
    }

    private var synthesizer: SpeechSynthesizer? = null
    private var connection: Connection? = null

    private fun closeSynthesizer() {
        if (synthesizer != null) {
            synthesizer!!.close()
        }
        if (connection != null) {
            connection!!.close()
        }
    }

    private fun createSynthesizer() {
        synthesizer?.close()
        connection?.close()
        synthesizer = SpeechSynthesizer(speechConfig)
        connection = Connection.fromSpeechSynthesizer(synthesizer)

        connection!!.connected.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizerConnected", null)
        }
        connection!!.disconnected.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizerDisconnected", null)
        }

        synthesizer!!.Synthesizing.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizing", null)
        }
        synthesizer!!.SynthesisStarted.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizerStarted", null)
        }
        synthesizer!!.SynthesisCompleted.addEventListener { _, e ->
            e.close()
            invokeMethod("azure_speech.onSynthesizerCompleted", null)
        }
        synthesizer!!.BookmarkReached.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizerBookmarkReached", null)
        }
        synthesizer!!.SynthesisCanceled.addEventListener { _, e ->
            val details = SpeechSynthesisCancellationDetails.fromResult(e.result)
            invokeMethod("azure_speech.onSynthesizerCanceled", details.errorDetails)
        }
        synthesizer!!.VisemeReceived.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizerVisemeReceived", null)
        }
        synthesizer!!.WordBoundary.addEventListener { _, _ ->
            invokeMethod("azure_speech.onSynthesizerWordBoundary", null)
        }
    }

    private fun startSynthesizing(call: MethodCall, result: Result) {
        runInBackground {
            val token: String = call.argument("token") ?: ""
            if (synthesizer == null || connection == null) {
                val success = buildSpeechConfig("", token, "", result)
                if (!success) return@runInBackground
                createSynthesizer()
            } else {
                synthesizer!!.StopSpeakingAsync().get()
                synthesizer!!.authorizationToken = token
                connection!!.openConnection(true)
            }
            if (synthesizer == null) {
                result.error("-11", "Failed to initialize synthesizer.", null)
                return@runInBackground
            }

            val options: Map<String, Any> = call.argument("options") ?: emptyMap()
            val text: String = options["text"] as? String ?: ""
            val identifier: String = options["identifier"] as? String ?: ""
            val role: String = options["role"] as? String ?: ""
            val style: String = options["style"] as? String ?: ""
            if (text.isEmpty() || identifier.isEmpty()) {
                result.error("-10", "`text` and `identifier` cannot be empty", null)
                return@runInBackground
            }
            val textEscaped = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&apos;")
            var mstts = ""
            if (role.isNotEmpty() || style.isNotEmpty()) {
                mstts += "<mstts:express-as "
                if (role.isNotEmpty()) {
                    mstts += "role=\"$role\" "
                }
                if (style.isNotEmpty()) {
                    mstts += "style=\"$style\""
                }
                mstts += ">$textEscaped</mstts:express-as>"
            } else {
                mstts = textEscaped
            }
            val ssml =
                "<speak version='1.0' xml:lang='en-US' xmlns='http://www.w3.org/2001/10/synthesis' xmlns:mstts='http://www.w3.org/2001/mstts'><voice name='$identifier'>$mstts</voice></speak>"
            synthesizer!!.SpeakSsml(ssml)
            result.success(null)
        }
    }

    private fun stopSynthesize(result: Result) {
        runInBackground {
            if (synthesizer != null) {
                synthesizer!!.StopSpeakingAsync()
            }
            result.success(null)
        }
    }
}
