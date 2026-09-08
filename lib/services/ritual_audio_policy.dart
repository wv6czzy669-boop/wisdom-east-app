import 'package:flutter/widgets.dart';

import '../controllers/ritual_sound_preference_controller.dart';

import '../localization/east_locale_registry.dart';

/// English has the existing spoken ritual cues. The arrival sound is an
/// intentional language-independent cue. Both respect the sound preference.
class RitualAudioPolicy {
  const RitualAudioPolicy._(this.locale, this.mode);

  factory RitualAudioPolicy.forLocale(Locale locale,
          {RitualSoundMode mode = RitualSoundMode.sound}) =>
      RitualAudioPolicy._(locale, mode);

  final Locale locale;
  final RitualSoundMode mode;

  bool get playsVoiceCues =>
      mode == RitualSoundMode.sound &&
      EastLocaleRegistry.canonicalTag(locale) == EastLocaleRegistry.english.tag;

  bool get playsRevealSound => mode == RitualSoundMode.sound;
}
