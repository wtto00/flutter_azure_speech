import AVFoundation
import Flutter
import MicrosoftCognitiveServicesSpeech
import UIKit

public class AzureSpeechPlugin: NSObject, FlutterPlugin {
  var channel: FlutterMethodChannel
  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "azure_speech", binaryMessenger: registrar.messenger())
    let instance = AzureSpeechPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "buildConfig":
      buildConfig(call, result: result)
    case "startRecognizing":
      startRecognizing(call, result: result)
    case "stopRecognition":
      stopRecognition(result: result)
    case "startSynthesizing":
      startSynthesizing(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var speechConfig: SPXSpeechConfiguration? = nil
  private func buildSpeechConfig(
    subscriptionKey: String, authorizationToken: String, region: String, result: FlutterResult
  ) -> Bool {
    if speechConfig == nil {
      if region.isEmpty {
        result(FlutterError(code: "-1", message: "region cannot be empty", details: nil))
        return false
      }
      if subscriptionKey.isEmpty && authorizationToken.isEmpty {
        result(
          FlutterError(
            code: "-2",
            message: "subscriptionKey and authorizationToken cannot be empty at the same time",
            details: nil))
        return false
      }
      do {
        if !subscriptionKey.isEmpty {
          self.speechConfig = try SPXSpeechConfiguration(
            subscription: subscriptionKey, region: region)
        } else {
          self.speechConfig = try SPXSpeechConfiguration(
            authorizationToken: authorizationToken, region: region)
        }
      } catch {
        result(FlutterError(code: "-3", message: "speechConfig initialize failed", details: nil))
        return false
      }
    } else if !authorizationToken.isEmpty {
      self.speechConfig!.authorizationToken = authorizationToken
    }
    return true
  }
  private func closeConfig() {
    if speechConfig != nil {
      speechConfig = nil
    }
  }
  private func buildConfig(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let subscriptionKey = args?["subscriptionKey"] as? String ?? ""
    let authorizationToken = args?["authorizationToken"] as? String ?? ""
    let region = args?["region"] as? String ?? ""
    let success = buildSpeechConfig(
      subscriptionKey: subscriptionKey, authorizationToken: authorizationToken, region: region,
      result: result)
    if success {
      result(true)
    }
  }

  private var recognizer: SPXSpeechRecognizer? = nil
  private var audioConfig: SPXAudioConfiguration? = nil
  private func createRecognizer() throws -> SPXSpeechRecognizer {
    audioConfig = SPXAudioConfiguration()
    recognizer = try SPXSpeechRecognizer(
      speechConfiguration: speechConfig!, audioConfiguration: audioConfig!)
    recognizer!.addRecognizingEventHandler({ _recognizer, args in
      self.channel.invokeMethod("azureSpeech.onRecognizing", arguments: args.result.text)
    })
    recognizer!.addRecognizedEventHandler({ _recognizer, args in
      let text = args.result.text ?? ""
      if !text.isEmpty {
        self.channel.invokeMethod("azureSpeech.onRecognized", arguments: text)
      }
    })
    recognizer!.addCanceledEventHandler({ _recognizer, args in
      self.channel.invokeMethod("azureSpeech.onRecognizerCanceled", arguments: args.errorDetails)
    })
    recognizer!.addSessionStartedEventHandler({ _recognizer, args in
      self.channel.invokeMethod("azureSpeech.onRecognizerSessionStarted", arguments: nil)
    })
    recognizer!.addSessionStoppedEventHandler({ _recognizer, args in
      self.channel.invokeMethod("azureSpeech.onRecognizerSessionStopped", arguments: nil)
    })
    recognizer!.addSpeechStartDetectedEventHandler { _recognizer, args in
      self.channel.invokeMethod("azureSpeech.onRecognizerStartDetected", arguments: nil)
    }
    recognizer!.addSpeechEndDetectedEventHandler { _recognizer, args in
      self.channel.invokeMethod("azureSpeech.onRecognizerEndDetected", arguments: nil)
    }
    return recognizer!
  }
  private func closeRecognizer() {
    if recognizer != nil {
      recognizer = nil
    }
    if audioConfig != nil {
      audioConfig = nil
    }
  }
  private func startRecognizing(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let token = args?["token"] as? String ?? ""
    let language = args?["language"] as? String ?? ""
    let success = buildSpeechConfig(
      subscriptionKey: "", authorizationToken: token, region: "", result: result)
    if !success { return }
    if !language.isEmpty {
      speechConfig!.speechRecognitionLanguage = language
    }
    speechConfig!.requestWordLevelTimestamps()
    do {
      if recognizer != nil {
        try recognizer?.stopContinuousRecognition()
        closeRecognizer()
      }
      recognizer = try createRecognizer()
      try recognizer!.startContinuousRecognition()
      result(nil)
    } catch {
      self.channel.invokeMethod(
        "azureSpeech.onException", arguments: "Exception: " + error.localizedDescription)
      result(FlutterError(code: "-4", message: error.localizedDescription, details: nil))
    }
  }
  private func stopRecognition(result: FlutterResult) {
    do {
      try recognizer?.stopContinuousRecognition()
      closeRecognizer()
      result(nil)
    } catch {
      self.channel.invokeMethod(
        "azureSpeech.onException", arguments: "Exception: " + error.localizedDescription)
      result(FlutterError(code: "-5", message: error.localizedDescription, details: nil))
    }
  }

  private var synthesizer: SPXSpeechSynthesizer? = nil
  private func createSynthesizer(_ token: String) throws {
    if synthesizer != nil {
      synthesizer!.authorizationToken = token
      return
    }
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(AVAudioSession.Category.playAndRecord)
    try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
    try audioSession.setActive(true)
    synthesizer = try SPXSpeechSynthesizer(speechConfig!)
    let connection = try SPXConnection(from: synthesizer!)
    connection.addConnectedEventHandler { _connection, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerConnected", arguments: nil)
    }
    connection.addDisconnectedEventHandler { _connection, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerDisconnected", arguments: nil)
    }
    connection.addMessageReceivedEventHandler { _connection, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerMessageReceived", arguments: nil)
    }
    synthesizer?.addSynthesizingEventHandler({ _synthesizer, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizing", arguments: nil)
    })
    synthesizer?.addSynthesisStartedEventHandler({ _synthesizer, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerStarted", arguments: nil)
    })
    synthesizer?.addSynthesisCompletedEventHandler({ _synthesizer, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerCompleted", arguments: nil)
    })
    synthesizer?.addBookmarkReachedEventHandler({ _synthesizer, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerBookmarkReached", arguments: nil)
    })
    synthesizer?.addSynthesisCanceledEventHandler({ _synthesizer, args in
      do {
        let details = try SPXSpeechSynthesisCancellationDetails(
          fromCanceledSynthesisResult: args.result)
        self.channel.invokeMethod(
          "azureSpeech.onSynthesizerCanceled", arguments: details.errorDetails)
      } catch {
      }
    })
    synthesizer?.addVisemeReceivedEventHandler({ _synthesizer, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerVisemeReceived", arguments: nil)
    })
    synthesizer?.addSynthesisWordBoundaryEventHandler({ _synthesizer, args in
      self.channel.invokeMethod("azureSpeech.onSynthesizerWordBoundary", arguments: nil)
    })
  }
  private func startSynthesizing(_ call: FlutterMethodCall, result: FlutterResult) {
    do {
      let args = call.arguments as? [String: Any]
      let token = args?["token"] as? String ?? ""
      if synthesizer == nil {
        let success = buildSpeechConfig(
          subscriptionKey: "", authorizationToken: token, region: "", result: result)
        if !success { return }
      }
      try createSynthesizer(token)
      let options = args?["options"] as? [String: Any]
      let text = options?["text"] as? String ?? ""
      let identifier = options?["identifier"] as? String ?? ""
      let role = options?["role"] as? String ?? ""
      let style = options?["style"] as? String ?? ""
      if text.isEmpty || identifier.isEmpty {
        result(
          FlutterError(
            code: "-10", message: "`text` and `identifier` cannot be empty", details: nil))
        return
      }
      let allowedCharacters = CharacterSet(charactersIn: "<>&'\"").inverted
      let textEscaped = text.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
      var mstts = ""
      if !role.isEmpty || !style.isEmpty {
        mstts.append("<mstts:express-as ")
        if !role.isEmpty {
          mstts.append("role=\"\(role)\"")
        }
        if !style.isEmpty {
          mstts.append("style=\"\(style)\"")
        }
        mstts.append(">\(textEscaped)</mstts:express-as>")
      } else {
        mstts.append(textEscaped)
      }
      let ssml =
        "<speak version='1.0' xml:lang='en-US' xmlns='http://www.w3.org/2001/10/synthesis' xmlns:mstts='http://www.w3.org/2001/mstts'><voice name='\(identifier)'>\(mstts)</voice></speak>"
      try synthesizer?.speakSsml(ssml)
      result(nil)
    } catch {
      self.channel.invokeMethod(
        "azureSpeech.onException", arguments: "Exception: " + error.localizedDescription)
      result(FlutterError(code: "-11", message: error.localizedDescription, details: nil))
    }
  }
  private func stopSynthesize(result: FlutterResult) {
    do {
      try synthesizer?.stopSpeaking()
      synthesizer = nil
      result(nil)
    } catch {
      self.channel.invokeMethod(
        "azureSpeech.onException", arguments: "Exception: " + error.localizedDescription)
      result(FlutterError(code: "-11", message: error.localizedDescription, details: nil))
    }
  }
}
