package wang.tato.azure_speech

import android.os.Handler
import android.os.Looper
import com.microsoft.cognitiveservices.speech.SpeechConfig
import com.microsoft.cognitiveservices.speech.SpeechRecognizer
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AzureSpeechPlugin */
class AzureSpeechPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    private lateinit var handler: Handler
    private fun invokeMethod(method: String, arguments: Any?) {
        handler.post {
            channel.invokeMethod(method, arguments)
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "azure_speech")
        channel.setMethodCallHandler(this)
        handler = Handler(Looper.getMainLooper())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        closeRecognizer();
        closeConfig();
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
                stopRecognition(call, result)
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
                result.error("-1", "region cannot be empty", {});
                return false;
            }
            if (subscriptionKey.isEmpty() && authorizationToken.isEmpty()) {
                result.error("-2",
                    "subscriptionKey and authorizationToken cannot be empty at the same time",
                    {});
                return false;
            }
            speechConfig = if (subscriptionKey.isNotEmpty()) {
                SpeechConfig.fromSubscription(subscriptionKey, region)
            } else {
                SpeechConfig.fromAuthorizationToken(authorizationToken, region)
            };

        } else if (authorizationToken.isNotEmpty()) {
            speechConfig!!.setAuthorizationToken(authorizationToken);
        }
        return true;
    }

    private fun closeConfig() {
        if (speechConfig != null) {
            speechConfig!!.close();
            speechConfig = null;
        }
    }

    private fun buildConfig(call: MethodCall, result: Result) {
        val subscriptionKey: String = call.argument("subscriptionKey") ?: ""
        val authorizationToken: String = call.argument("authorizationToken") ?: ""
        val region: String = call.argument("region") ?: ""
        val success = buildSpeechConfig(subscriptionKey, authorizationToken, region, result);
        if (success) result.success(true);
    }

    private var recognizer: SpeechRecognizer? = null;
    private var audioConfig: AudioConfig? = null;
    private var microphoneStream: MicrophoneStream? = null
    private fun createRecognizer(): SpeechRecognizer {
        microphoneStream = MicrophoneStream(onVolumeChange = { volume: Double ->
            invokeMethod(
                "azureSpeech.onVolumeChange",
                volume
            )
        })
        audioConfig = AudioConfig.fromStreamInput(microphoneStream)
        recognizer = SpeechRecognizer(speechConfig, audioConfig)

        recognizer!!.recognizing.addEventListener { _, speechRecognitionResultEventArgs ->
            val text = speechRecognitionResultEventArgs.result.text
            invokeMethod("azureSpeech.onRecognizing", text)
        }
        recognizer!!.recognized.addEventListener { _, speechRecognitionResultEventArgs ->
            val text = speechRecognitionResultEventArgs.result.text;
            if (text.isNotEmpty()) invokeMethod("azureSpeech.onRecognized", text)
        }
        recognizer!!.canceled.addEventListener { _, speechRecognitionCanceledEventArgs ->
            invokeMethod(
                "azureSpeech.onRecognizerCanceled",
                speechRecognitionCanceledEventArgs.errorCode.toString(),
            )
        }
        recognizer!!.sessionStarted.addEventListener { _, _ ->
            invokeMethod("azureSpeech.onRecognizerSessionStarted", null)
        }
        recognizer!!.sessionStopped.addEventListener { _, _ ->
            invokeMethod("azureSpeech.onRecognizerSessionStopped", null)
        }
        return recognizer!!
    }

    private fun closeRecognizer() {
        if (microphoneStream != null) {
            microphoneStream!!.close();
            microphoneStream = null;
        }
        if (recognizer != null) {
            recognizer!!.close();
            recognizer = null;
        }
        if (audioConfig != null) {
            audioConfig!!.close();
            audioConfig = null;
        }
    }

    private fun startRecognizing(call: MethodCall, result: Result) {
        try {
            val token: String = call.argument("token") ?: ""
            val language: String = call.argument("language") ?: ""
            val success = buildSpeechConfig("", token, "", result);
            if (!success) return;
            if (language.isNotEmpty()) speechConfig!!.setSpeechRecognitionLanguage(language);
            speechConfig!!.requestWordLevelTimestamps();
            if (recognizer != null) {
                recognizer!!.stopContinuousRecognitionAsync().get();
                closeRecognizer();
            }
            recognizer = createRecognizer();
            recognizer!!.startContinuousRecognitionAsync();
            result.success(null);
        } catch (e: Exception) {
            channel.invokeMethod("azureSpeech.onException", "Exception: " + e.message)
        }
    }

    private fun stopRecognition(call: MethodCall, result: Result) {
        if (recognizer != null) {
            recognizer!!.stopContinuousRecognitionAsync().get();
        }
        closeRecognizer();
        result.success(null);
    }

}
