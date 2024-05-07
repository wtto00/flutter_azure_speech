import AVFoundation
import Flutter
import MicrosoftCognitiveServicesSpeech

extension AVAudioPCMBuffer {
  func data() -> Data {
    var nBytes = 0
    nBytes = Int(self.frameLength * (self.format.streamDescription.pointee.mBytesPerFrame))
    var range: NSRange = NSRange()
    range.location = 0
    range.length = nBytes
    let buffer = NSMutableData()
    buffer.replaceBytes(in: range, withBytes: (self.int16ChannelData![0]))
    return buffer as Data
  }

  var duration: TimeInterval {
    format.sampleRate > 0 ? .init(frameLength) / format.sampleRate : 0
  }
}

public class AzureSpeechPlugin: NSObject, FlutterPlugin {
  let channel: FlutterMethodChannel
  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }
  public static func register(with registrar: FlutterPluginRegistrar) {
    let taskQueue = registrar.messenger().makeBackgroundTaskQueue?()
    let channel = FlutterMethodChannel(
      name: "azure_speech", binaryMessenger: registrar.messenger(),
      codec: FlutterStandardMethodCodec.sharedInstance(), taskQueue: taskQueue)
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
    case "stopSynthesize":
      stopSynthesize(result: result)
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
    runInBackground {
      let args = call.arguments as? [String: Any]
      let subscriptionKey = args?["subscriptionKey"] as? String ?? ""
      let authorizationToken = args?["authorizationToken"] as? String ?? ""
      let region = args?["region"] as? String ?? ""
      let success = self.buildSpeechConfig(
        subscriptionKey: subscriptionKey, authorizationToken: authorizationToken, region: region,
        result: result)
      if success {
        result(true)
      }
    }
  }

  private let audioEngine: AVAudioEngine = AVAudioEngine()
  private var recognizer: SPXSpeechRecognizer? = nil
  private var audioConfig: SPXAudioConfiguration? = nil
  private var pushStream: SPXPushAudioInputStream? = nil
  private func closeRecognizer() {
    if recognizer != nil {
      recognizer = nil
    }
    if audioConfig != nil {
      audioConfig = nil
    }
  }
  private func createRecognizer() throws {
    pushStream = SPXPushAudioInputStream()
    audioConfig = SPXAudioConfiguration(streamInput: pushStream!)
    recognizer = try SPXSpeechRecognizer(
      speechConfiguration: speechConfig!, audioConfiguration: audioConfig!)
    recognizer!.addRecognizingEventHandler({ _recognizer, args in
      self.invokeMethod("azure_speech.onRecognizing", arguments: args.result.text)
    })
    recognizer!.addRecognizedEventHandler({ _recognizer, args in
      let text = args.result.text ?? ""
      if !text.isEmpty {
        self.invokeMethod("azure_speech.onRecognized", arguments: text)
      }
    })
    recognizer!.addCanceledEventHandler({ _recognizer, args in
      self.invokeMethod("azure_speech.onRecognizerCanceled", arguments: args.errorDetails)
    })
    recognizer!.addSessionStartedEventHandler({ _recognizer, args in
      self.invokeMethod("azure_speech.onRecognizerSessionStarted", arguments: nil)
    })
    recognizer!.addSessionStoppedEventHandler({ _recognizer, args in
      self.invokeMethod("azure_speech.onRecognizerSessionStopped", arguments: nil)
    })
    recognizer!.addSpeechStartDetectedEventHandler { _recognizer, args in
      self.invokeMethod("azure_speech.onRecognizerStartDetected", arguments: nil)
    }
    recognizer!.addSpeechEndDetectedEventHandler { _recognizer, args in
      self.invokeMethod("azure_speech.onRecognizerEndDetected", arguments: nil)
    }
  }
  private func startRecognizing(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    runInBackground {
      let args = call.arguments as? [String: Any]
      let token = args?["token"] as? String ?? ""
      let language = args?["language"] as? String ?? ""
      let success = self.buildSpeechConfig(
        subscriptionKey: "", authorizationToken: token, region: "", result: result)
      if !success { return }
      if !language.isEmpty {
        self.speechConfig!.speechRecognitionLanguage = language
      }
      self.speechConfig!.requestWordLevelTimestamps()
      do {
        if self.recognizer != nil {
          try self.recognizer?.stopContinuousRecognition()
          self.closeRecognizer()
        }
        try self.createRecognizer()
        try self.recognizer!.startContinuousRecognition()
        self.readDataFromMicrophone()
        result(nil)
      } catch {
        self.invokeMethod(
          "azure_speech.onException", arguments: "Exception: " + error.localizedDescription)
        result(FlutterError(code: "-4", message: error.localizedDescription, details: nil))
      }
    }
  }
  private func readDataFromMicrophone() {
    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    let recordingFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)

    guard let formatConverter = AVAudioConverter(from: inputFormat, to: recordingFormat!)
    else {
      return
    }
    // Install a tap on the audio engine with the buffer size and the input format.
    audioEngine.inputNode.installTap(
      onBus: 0, bufferSize: AVAudioFrameCount(2048), format: inputFormat
    ) { (buffer, time) in
      let outputBufferCapacity = AVAudioFrameCount(buffer.duration * recordingFormat!.sampleRate)

        // 获取实时音量
        let channelDataValue = buffer.floatChannelData?.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map{ channelDataValue?[$0] ?? 0 }
        let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(rms)
        let volume = pow(10, avgPower / 20) * 100
        self.invokeMethod("azure_speech.onVolumeChange", arguments: volume)
        
      guard
        let pcmBuffer = AVAudioPCMBuffer(
          pcmFormat: recordingFormat!, frameCapacity: outputBufferCapacity)
      else {
        print("Failed to create new pcm buffer")
        return
      }
      pcmBuffer.frameLength = outputBufferCapacity

      var error: NSError? = nil
      let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
        outStatus.pointee = AVAudioConverterInputStatus.haveData
        return buffer
      }
      formatConverter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)

      if error != nil {
        print(error!.localizedDescription)
      } else {
        self.pushStream?.write((pcmBuffer.data()))
      }
    }
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      print(error.localizedDescription)
    }
  }
  private func stopRecognition(result: @escaping FlutterResult) {
    runInBackground {
      do {
        try self.recognizer?.stopContinuousRecognition()
        self.audioEngine.stop()
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.pushStream?.close()
        self.pushStream = nil
        self.closeRecognizer()
        result(nil)
      } catch {
        self.invokeMethod(
          "azure_speech.onException", arguments: "Exception: " + error.localizedDescription)
        result(FlutterError(code: "-5", message: error.localizedDescription, details: nil))
      }
    }
  }

  private var synthesizer: SPXSpeechSynthesizer? = nil
  private var connection: SPXConnection? = nil
  private func createSynthesizer(_ token: String) throws {
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(AVAudioSession.Category.playAndRecord)
    try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
    try audioSession.setActive(true)
    synthesizer = try SPXSpeechSynthesizer(speechConfig!)
    connection = try SPXConnection(from: synthesizer!)
    connection!.addConnectedEventHandler { _connection, args in
      self.invokeMethod("azure_speech.onSynthesizerConnected", arguments: nil)
    }
    connection!.addDisconnectedEventHandler { _connection, args in
      self.invokeMethod("azure_speech.onSynthesizerDisconnected", arguments: nil)
    }
    synthesizer?.addSynthesizingEventHandler({ _synthesizer, args in
      self.invokeMethod("azure_speech.onSynthesizing", arguments: nil)
    })
    synthesizer?.addSynthesisStartedEventHandler({ _synthesizer, args in
      self.invokeMethod("azure_speech.onSynthesizerStarted", arguments: nil)
    })
    synthesizer?.addSynthesisCompletedEventHandler({ _synthesizer, args in
      self.invokeMethod("azure_speech.onSynthesizerCompleted", arguments: nil)
      do {
        try self._stopSynthesize()
      } catch {
        self.invokeMethod(
          "azure_speech.onException", arguments: "Exception: " + error.localizedDescription)
      }
    })
    synthesizer?.addBookmarkReachedEventHandler({ _synthesizer, args in
      self.invokeMethod("azure_speech.onSynthesizerBookmarkReached", arguments: nil)
    })
    synthesizer?.addSynthesisCanceledEventHandler({ _synthesizer, args in
      do {
        let details = try SPXSpeechSynthesisCancellationDetails(
          fromCanceledSynthesisResult: args.result)
        self.invokeMethod(
          "azure_speech.onSynthesizerCanceled", arguments: details.errorDetails)
      } catch {
        self.invokeMethod(
          "azure_speech.onException", arguments: "Exception: " + error.localizedDescription)
      }
    })
    synthesizer?.addVisemeReceivedEventHandler({ _synthesizer, args in
      self.invokeMethod("azure_speech.onSynthesizerVisemeReceived", arguments: nil)
    })
    synthesizer?.addSynthesisWordBoundaryEventHandler({ _synthesizer, args in
      self.invokeMethod("azure_speech.onSynthesizerWordBoundary", arguments: nil)
    })
  }
  private func startSynthesizing(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    runInBackground {
      do {
        let args = call.arguments as? [String: Any]
        let token = args?["token"] as? String ?? ""
        if self.synthesizer != nil {
          try self._stopSynthesize()
        }
        let success = self.buildSpeechConfig(
          subscriptionKey: "", authorizationToken: token, region: "", result: result)
        if !success { return }
        try self.createSynthesizer(token)
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
        let textEscaped =
          text
          .replacingOccurrences(of: "&", with: "&amp;")
          .replacingOccurrences(of: "<", with: "&lt;")
          .replacingOccurrences(of: ">", with: "&gt;")
          .replacingOccurrences(of: "\"", with: "&quot;")
          .replacingOccurrences(of: "''", with: "&#39;")
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
        try self.synthesizer?.speakSsml(ssml)
        result(nil)
      } catch {
        self.invokeMethod(
          "azure_speech.onException", arguments: "Exception: " + error.localizedDescription)
        result(FlutterError(code: "-11", message: error.localizedDescription, details: nil))
      }
    }
  }
  private func _stopSynthesize() throws {
    try synthesizer?.stopSpeaking()
    connection?.close()
    synthesizer = nil
    connection = nil
  }
  private func stopSynthesize(result: @escaping FlutterResult) {
    runInBackground {
      do {
        try self._stopSynthesize()
        result(nil)
      } catch {
        self.invokeMethod(
          "azure_speech.onException", arguments: "Exception: " + error.localizedDescription)
        result(FlutterError(code: "-11", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func runInBackground(_ handler: @escaping () -> Void) {
    DispatchQueue.global(qos: .background).async {
      handler()
    }
  }
  private func invokeMethod(_ method: String, arguments: Any?) {
    DispatchQueue.main.async {
      self.channel.invokeMethod(method, arguments: arguments)
    }
  }
}
