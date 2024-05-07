import 'package:azure_speech/speech_role.dart';
import 'package:azure_speech/speech_style.dart';

class SynthesizerOption {
  SynthesizerOption({
    required this.text,
    required this.identifier,
    this.role,
    this.style,
  });

  final String text;

  /// Voice name.
  /// See: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts
  final String identifier;

  /// See: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-voice#use-speaking-styles-and-roles
  final SpeechRole? role;

  /// See: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-voice#use-speaking-styles-and-roles
  final SpeechStyle? style;

  Map<String, String?> toJson() {
    return <String, String?>{
      'text': text,
      'identifier': identifier,
      'role': role?.toString(),
      'style': style?.name,
    };
  }
}
