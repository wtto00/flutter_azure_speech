import 'package:flutter/material.dart';
import 'dart:async';

import 'package:azure_speech/azure_speech.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final TextEditingController _controller;
  late final ScrollController _scrollController;
  late final AzureSpeech _azureSpeech;

  @override
  void initState() {
    _controller = TextEditingController();
    _scrollController = ScrollController();
    _azureSpeech = AzureSpeech();
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller.dispose();
    _azureSpeech.stopRecognition();
    super.dispose();
  }

  void _appendLogText(String text) {
    _controller.text += '\n$text';
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _clear() {
    _controller.clear();
  }

  String _token =
      'eyJhbGciOiJFUzI1NiIsImtpZCI6ImtleTEiLCJ0eXAiOiJKV1QifQ.eyJyZWdpb24iOiJzb3V0aGVhc3Rhc2lhIiwic3Vic2NyaXB0aW9uLWlkIjoiNTcyMDMwNmEzOTY0NGMxY2E2OTZlZGFjYjlmYzU1MmQiLCJwcm9kdWN0LWlkIjoiU3BlZWNoU2VydmljZXMuRjAiLCJjb2duaXRpdmUtc2VydmljZXMtZW5kcG9pbnQiOiJodHRwczovL2FwaS5jb2duaXRpdmUubWljcm9zb2Z0LmNvbS9pbnRlcm5hbC92MS4wLyIsImF6dXJlLXJlc291cmNlLWlkIjoiL3N1YnNjcmlwdGlvbnMvMTQ5NmQ5ZDktZGQzYi00ZjU3LTk3YWEtZmUzMzYxZGJhNDAwL3Jlc291cmNlR3JvdXBzL2FpZnVuLXZvaWNlL3Byb3ZpZGVycy9NaWNyb3NvZnQuQ29nbml0aXZlU2VydmljZXMvYWNjb3VudHMvYWlmdW4tc291dGhlYXN0Iiwic2NvcGUiOiJzcGVlY2hzZXJ2aWNlcyIsImF1ZCI6InVybjptcy5zcGVlY2hzZXJ2aWNlcy5zb3V0aGVhc3Rhc2lhIiwiZXhwIjoxNzE0NDgwNjgyLCJpc3MiOiJ1cm46bXMuY29nbml0aXZlc2VydmljZXMifQ.WRPsr3-iGG6TuorWVOrXm8LcJHBVFAQ0nqAjdRMK49MV01oD_V3j7LoKvCROW98u1K1tuGYiquNfEZojotI_dg';

  Future<void> _prepareToken() async {
    // TODO: Refresh token if token is expired
    // _token = 'xxx'
  }

  bool _isInited = false;

  Future<void> _init() async {
    // TODO: get authorizationToken from server api
    // https://learn.microsoft.com/en-US/azure/ai-services/authentication#authenticate-with-an-access-token
    await _prepareToken();
    _isInited = await _azureSpeech.initialize(
      region: 'southeastasia',
      authorizationToken: _token,
    );
    if (_isInited) {
      _azureSpeech.onRecognizing = (text) {
        _appendLogText('recognizing: $text');
      };
      _azureSpeech.onRecognized = (text) {
        _appendLogText("recognized: $text");
      };
      _azureSpeech.onRecognizerCanceled = (reason) {
        _appendLogText('recognizerCanceled: $reason');
      };
      _azureSpeech.onRecognizerSessionStarted = () {
        _appendLogText('recognizerSessionStarted');
        setState(() {
          _isRecognizing = true;
        });
      };
      _azureSpeech.onRecognizerSessionStopped = () {
        _appendLogText('recognizerSessionStopped');
        setState(() {
          _isRecognizing = false;
        });
      };
      _azureSpeech.onVolumeChange =(volume) {
        _appendLogText('VolumeChange: $volume');
      };
    }
  }

  bool _isSynthesizing = false;

  void _startSynthesizing() {}

  void _stopSynthesizing() {}

  Future<bool> _requestPermission() async {
    final PermissionStatus status = await Permission.microphone.request();

    if (status.isPermanentlyDenied) {
      // 永久拒绝
      _appendLogText('Permission microphone is permanently denied.');
      return false;
    }

    if (!status.isGranted && !status.isLimited) {
      _appendLogText('Permission microphone is not granted.');
      return false;
    }
    return true;
  }

  bool _isRecognizing = false;

  Future<void> _startRecognizing() async {
    final permission = await _requestPermission();
    if (!permission) return;
    if (!_isInited) {
      _appendLogText('Speech is not inited.');
      return;
    }
    await _prepareToken();
    _azureSpeech.startRecognizing(
      token: _token,
      language: 'zh-CN',
      silenceTimeout: const Duration(seconds: 3),
    );
  }

  void _stopRecognition() {
    _azureSpeech.stopRecognition();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Azure Speech Example App'),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _controller,
                scrollController: _scrollController,
                maxLines: 10,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  FilledButton(
                    onPressed: _startSynthesizing,
                    child: const Text('Start Synthesizing'),
                  ),
                  FilledButton(
                    onPressed: _isSynthesizing ? _stopSynthesizing : null,
                    child: const Text('Stop Synthesizing'),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  FilledButton(
                    onPressed: _isRecognizing ? null : _startRecognizing,
                    child: const Text('Start Recognizing'),
                  ),
                  FilledButton(
                    onPressed: _isRecognizing ? _stopRecognition : null,
                    child: const Text('Stop Recognizing'),
                  ),
                ],
              ),
              FilledButton(onPressed: _clear, child: const Text('Clear'))
            ],
          ),
        ),
      ),
    );
  }
}