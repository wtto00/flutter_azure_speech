import 'dart:async';

import 'package:azure_speech/synthesizer_option.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef TextResultHandler = void Function(String text);
typedef ExceptionResultHandler = void Function(String err);
typedef ReasonResultHandler = void Function(String reason);
typedef VolumeResultHandler = void Function(double volume);

class AzureSpeech {
  static const _methodChannel = MethodChannel('azure_speech');
  AzureSpeech() {
    _methodChannel.setMethodCallHandler(_onMethodCall);
  }

  // Exception handler.
  ExceptionResultHandler? onException;
  // Recognizing handler.
  TextResultHandler? onRecognizing;
  // The recognition of a paragraph has ended. However, the recognition has not ended.
  TextResultHandler? onRecognized;
  // Recognizer canceled handler. It will be triggered If authorizationToken is expired.
  ReasonResultHandler? onRecognizerCanceled;
  // Recognizer has been started.
  VoidCallback? onRecognizerSessionStarted;
  // Recognizer has been stopped.
  VoidCallback? onRecognizerSessionStopped;
  // Recognizer Start Detected.
  VoidCallback? onRecognizerStartDetected;
  // Recognizer End Detected.
  VoidCallback? onRecognizerEndDetected;
  // volume changed
  VolumeResultHandler? onVolumeChange;
  // Synthesizer Connecte
  VoidCallback? onSynthesizerConnected;
  // Synthesizer Disconnecte
  VoidCallback? onSynthesizerDisconnected;
  // Synthesizing
  VoidCallback? onSynthesizing;
  // Synthesizer Started
  VoidCallback? onSynthesizerStarted;
  // Synthesizer Completed
  VoidCallback? onSynthesizerCompleted;
  // Synthesizer Bookmark Reached
  VoidCallback? onSynthesizerBookmarkReached;
  // Synthesizer Canceled
  ReasonResultHandler? onSynthesizerCanceled;
  // Synthesizer Viseme Received
  VoidCallback? onSynthesizerVisemeReceived;
  // Synthesizer Word Boundary
  VoidCallback? onSynthesizerWordBoundary;

  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case "azure_speech.onRecognizing":
        onRecognizing?.call(call.arguments);
        _clearRecognizerTimer();
        break;
      case "azure_speech.onRecognized":
        onRecognized?.call(call.arguments);
        if (_silenceTimeout.compareTo(Duration.zero) > 0) {
          _recognizerTimer = Timer(_silenceTimeout, () {
            stopRecognition();
          });
        }
        break;
      case "azure_speech.onRecognizerCanceled":
        onRecognizerCanceled?.call(call.arguments);
        break;
      case "azure_speech.onRecognizerSessionStarted":
        onRecognizerSessionStarted?.call();
        _clearRecognizerTimer();
        if (_silenceTimeout.compareTo(Duration.zero) > 0) {
          _recognizerTimer = Timer(_silenceTimeout, () {
            stopRecognition();
          });
        }
        break;
      case "azure_speech.onRecognizerSessionStopped":
        onRecognizerSessionStopped?.call();
        break;
      case "azure_speech.onRecognizerStartDetected":
        onRecognizerStartDetected?.call();
        break;
      case "azure_speech.onRecognizerEndDetected":
        onRecognizerEndDetected?.call();
        break;
      case "azure_speech.onException":
        onException?.call(call.arguments);
        break;
      case "azure_speech.onVolumeChange":
        onVolumeChange?.call(call.arguments);
        break;
      case "azure_speech.onSynthesizerConnected":
        onSynthesizerConnected?.call();
        break;
      case "azure_speech.onSynthesizerDisconnected":
        onSynthesizerDisconnected?.call();
        break;
      case "azure_speech.onSynthesizing":
        onSynthesizing?.call();
        break;
      case "azure_speech.onSynthesizerStarted":
        onSynthesizerStarted?.call();
        break;
      case "azure_speech.onSynthesizerCompleted":
        onSynthesizerCompleted?.call();
        break;
      case "azure_speech.onSynthesizerBookmarkReached":
        onSynthesizerBookmarkReached?.call();
        break;
      case "azure_speech.onSynthesizerCanceled":
        onSynthesizerCanceled?.call(call.arguments);
        break;
      case "azure_speech.onSynthesizerVisemeReceived":
        onSynthesizerVisemeReceived?.call();
        break;
      case "azure_speech.onSynthesizerWordBoundary":
        onSynthesizerWordBoundary?.call();
        break;
      default:
        debugPrint("Error: method `${call.method}` not found");
    }
  }

  /// build SpeechConfig
  /// [subscriptionKey] SubscriptionKey of Azure Speech resource.
  ///
  /// [authorizationToken] Authorization Token in Azure from server.
  /// See: https://learn.microsoft.com/en-us/azure/ai-services/authentication#authenticate-with-an-access-token
  ///
  /// [region] Region of Azure Speech resource.
  Future<bool> initialize({
    String? subscriptionKey,
    String? authorizationToken,
    required String region,
  }) async {
    return await _methodChannel.invokeMethod<bool>('buildConfig', {
          'subscriptionKey': subscriptionKey,
          'authorizationToken': authorizationToken,
          'region': region,
        }) ??
        false;
  }

  /// Silence timeout for listening.
  Duration _silenceTimeout = Duration.zero;
  Timer? _recognizerTimer;
  void _clearRecognizerTimer() {
    if (_recognizerTimer?.isActive == true) {
      _recognizerTimer!.cancel();
    }
  }

  /// Start recognizing
  ///
  /// [token] Authorization Token from service.
  /// If null, will use last [authorizationToken] or [subscriptionKey] in initializeRecognizer.
  ///
  /// [language] default is `en-US`.
  /// All supported languages to see: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=stt
  ///
  /// [silenceTimeout] Silence timeout for listening.
  /// If null. will use last [silenceTimeout].
  /// If <= 0, will not be stopped automatically.
  Future startRecognizing({
    String? token,
    String language = 'en-US',
    Duration? silenceTimeout,
  }) {
    if (silenceTimeout != null) _silenceTimeout = silenceTimeout;
    return _methodChannel.invokeMethod('startRecognizing', {
      'token': token,
      'language': language,
    });
  }

  /// Stop recognizing
  Future stopRecognition() {
    _clearRecognizerTimer();
    return _methodChannel.invokeMethod('stopRecognition');
  }

  /// Start Synthesizing
  Future startSynthesizing({String? token, required SynthesizerOption options}) {
    return _methodChannel.invokeMethod('startSynthesizing', {
      'token': token,
      'options': options.toJson(),
    });
  }

  /// Stop Synthesize
  Future stopSynthesize() {
    return _methodChannel.invokeMethod('stopSynthesize');
  }
}
