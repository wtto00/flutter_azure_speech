import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef TextResultHandler = void Function(String text);
typedef ExceptionResultHandler = void Function(String err);
typedef ReasonResultHandler = void Function(String reason);
typedef VolumeResultHandler = void Function(double volume);

class AzureSpeech {
  static const methodChannel = MethodChannel('azure_speech');
  AzureSpeech() {
    methodChannel.setMethodCallHandler(_onMethodCall);
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
  // Synthesizer Message Received
  VoidCallback? onSynthesizerMessageReceived;
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
      case "azureSpeech.onRecognizing":
        onRecognizing?.call(call.arguments);
        _clearRecognizerTimer();
        break;
      case "azureSpeech.onRecognized":
        onRecognized?.call(call.arguments);
        if (_silenceTimeout.compareTo(Duration.zero) > 0) {
          _recognizerTimer = Timer(_silenceTimeout, () {
            stopRecognition();
          });
        }
        break;
      case "azureSpeech.onRecognizerCanceled":
        onRecognizerCanceled?.call(call.arguments);
        break;
      case "azureSpeech.onRecognizerSessionStarted":
        onRecognizerSessionStarted?.call();
        _clearRecognizerTimer();
        if (_silenceTimeout.compareTo(Duration.zero) > 0) {
          _recognizerTimer = Timer(_silenceTimeout, () {
            stopRecognition();
          });
        }
        break;
      case "azureSpeech.onRecognizerSessionStopped":
        onRecognizerSessionStopped?.call();
        break;
      case "azureSpeech.onException":
        onException?.call(call.arguments);
        break;
      case "azureSpeech.onVolumeChange":
        onVolumeChange?.call(call.arguments);
        break;
      case "azureSpeech.onSynthesizerConnected":
        onSynthesizerConnected?.call();
        break;
      case "azureSpeech.onSynthesizerDisconnected":
        onSynthesizerDisconnected?.call();
        break;
      case "azureSpeech.onSynthesizerMessageReceived":
        onSynthesizerMessageReceived?.call();
        break;
      case "azureSpeech.onSynthesizing":
        onSynthesizing?.call();
        break;
      case "azureSpeech.onSynthesizerStarted":
        onSynthesizerStarted?.call();
        break;
      case "azureSpeech.onSynthesizerCompleted":
        onSynthesizerCompleted?.call();
        break;
      case "azureSpeech.onSynthesizerBookmarkReached":
        onSynthesizerBookmarkReached?.call();
        break;
      case "azureSpeech.onSynthesizerCanceled":
        onSynthesizerCanceled?.call(call.arguments);
        break;
      case "azureSpeech.onSynthesizerVisemeReceived":
        onSynthesizerVisemeReceived?.call();
        break;
      case "azureSpeech.onSynthesizerWordBoundary":
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
    return await methodChannel.invokeMethod<bool>('buildConfig', {
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

  /// start recognizing
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
    return methodChannel.invokeMethod('startRecognizing', {
      'token': token,
      'language': language,
    });
  }

  /// stop recognizing
  Future stopRecognition() {
    _clearRecognizerTimer();
    return methodChannel.invokeMethod('stopRecognition');
  }
}
