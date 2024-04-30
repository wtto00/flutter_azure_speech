/// The voice-specific speaking style.
/// https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-voice
enum SpeechStyle {
  advertisementUpbeat('advertisement_upbeat'),
  affectionate('affectionate'),
  angry('angry'),
  assistant('assistant'),
  calm('calm'),
  chat('chat'),
  cheerful('cheerful'),
  customerservice('customerservice'),
  depressed('depressed'),
  disgruntled('disgruntled'),
  documentaryNarration('documentary-narration'),
  embarrassed('embarrassed'),
  empathetic('empathetic'),
  envious('envious'),
  excited('excited'),
  fearful('fearful'),
  friendly('friendly'),
  gentle('gentle'),
  hopeful('hopeful'),
  lyrical('lyrical'),
  narrationProfessional('narration-professional'),
  narrationRelaxed('narration-relaxed'),
  newscast('newscast'),
  newscastCasual('newscast-casual'),
  newscastFormal('newscast-formal'),
  poetryReading('poetry-reading'),
  sad('sad'),
  serious('serious'),
  shouting('shouting'),
  sportsCommentary('sports_commentary'),
  sportsCommentaryExcited('sports_commentary_excited'),
  whispering('whispering'),
  terrified('terrified'),
  unfriendly('unfriendly');

  final String name;
  const SpeechStyle(this.name);
}
