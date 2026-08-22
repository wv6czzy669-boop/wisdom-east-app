import 'package:flutter/widgets.dart';

import '../localization/east_locale_registry.dart';

/// English has the existing spoken ritual cues. The arrival sound is an
/// intentional language-independent cue and always remains audible.
class RitualAudioPolicy {
  const RitualAudioPolicy._(this.locale);

  factory RitualAudioPolicy.forLocale(Locale locale) =>
      RitualAudioPolicy._(locale);

  final Locale locale;

  bool get playsVoiceCues =>
      EastLocaleRegistry.canonicalTag(locale) == EastLocaleRegistry.english.tag;

  bool get playsRevealSound => true;
}
