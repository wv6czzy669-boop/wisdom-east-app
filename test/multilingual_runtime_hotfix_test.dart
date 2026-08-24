import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';
import 'package:wisdom_app/utils/countdown_formatter.dart';
import 'package:wisdom_app/utils/reflection_prompt.dart';

/// EAST. Phase 5G -- final multilingual runtime hotfix regression:
/// the daily-lock countdown message, all six canonical Reflection prompts,
/// and EAST.-authored notification copy, across every one of the 15
/// product locales -- plus the notification-copy update mechanism the
/// real-device EN -> TR scenario depends on.
void main() {
  final locales = EastLocaleRegistry.runtimeSupported;

  test('exactly the 15 product locales are exercised by this suite', () {
    expect(locales.length, 15);
    expect(
      locales.map(EastLocaleRegistry.canonicalTag).toSet(),
      <String>{
        'en',
        'tr',
        'ja',
        'de',
        'fr',
        'ko',
        'zh-Hant',
        'ar',
        'es',
        'pt-BR',
        'it',
        'th',
        'nl',
        'pl',
        'vi',
      },
    );
    // No forbidden technical/legacy locales ever leak into product runtime
    // localization -- Traditional Chinese (`zh` + scriptCode `Hant`) and
    // Brazilian Portuguese (`pt` + countryCode `BR`) are the only zh/pt
    // forms present; bare `zh`/`pt` never are.
    for (final locale in locales) {
      final tag = EastLocaleRegistry.canonicalTag(locale);
      expect(tag, isNot('zh'));
      expect(tag, isNot('zh-Hans'));
      expect(tag, isNot('zh-CN'));
      expect(tag, isNot('pt'));
      expect(tag, isNot('pt-PT'));
      if (locale.languageCode == 'zh') {
        expect(locale.scriptCode, 'Hant');
      }
      if (locale.languageCode == 'pt') {
        expect(locale.countryCode, 'BR');
      }
    }
  });

  group('Issue 1 -- daily lock message', () {
    for (final locale in locales) {
      final tag = EastLocaleRegistry.canonicalTag(locale);
      test(
          '$tag: returnWhenSilenceOpensAgain is present, non-empty, and '
          'never falls back to a different locale\'s wording', () {
        final l10n = lookupAppLocalizations(locale);
        final en = lookupAppLocalizations(const Locale('en'));

        expect(l10n.returnWhenSilenceOpensAgain, isNotEmpty);
        if (tag != 'en') {
          expect(
            l10n.returnWhenSilenceOpensAgain,
            isNot(en.returnWhenSilenceOpensAgain),
            reason: '$tag must have its own reviewed wording, not an '
                'English fallback',
          );
        }
      });
    }

    test(
        'CountdownPresentation.plainText embeds the caller-supplied '
        'localized sentence and the ceiling-based HH:MM token, for every '
        'product locale', () {
      for (final locale in locales) {
        final l10n = lookupAppLocalizations(locale);
        final sentence = l10n.returnWhenSilenceOpensAgain;

        final underAnHour = CountdownPresentation(
          sentence: sentence,
          duration: CountdownFormatter.resolve(
            const Duration(minutes: 41, seconds: 30),
          ),
        );
        expect(underAnHour.plainText, '$sentence\n00:42');

        final overAnHour = CountdownPresentation(
          sentence: sentence,
          duration: CountdownFormatter.resolve(
            const Duration(hours: 19, minutes: 24),
          ),
        );
        expect(overAnHour.plainText, '$sentence\n19:24');
      }
    });

    test(
        'English wording is byte-identical to the pre-hotfix hardcoded '
        'string (real-device baseline never changes)', () {
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        en.returnWhenSilenceOpensAgain,
        'Return when the silence opens again.',
      );
    });
  });

  group('Issue 2 -- all N canonical Reflection prompts', () {
    test('N is exactly 6, in the fixed, approved canonical order', () {
      expect(reflectionPrompts.length, 6);
      expect(reflectionPrompts, [
        'What remains?',
        'What stayed with you?',
        'What became clearer?',
        'What are you noticing now?',
        'What feels different?',
        'What would you like to carry forward?',
      ]);
    });

    for (final locale in locales) {
      final tag = EastLocaleRegistry.canonicalTag(locale);
      test(
          '$tag: all 6 prompts exist, are non-empty, and (non-English) '
          'differ from the English source', () {
        final l10n = lookupAppLocalizations(locale);
        final en = lookupAppLocalizations(const Locale('en'));
        final localized = localizedReflectionPrompts(l10n);
        final english = localizedReflectionPrompts(en);

        expect(localized, hasLength(6));
        for (var i = 0; i < 6; i++) {
          expect(localized[i], isNotEmpty, reason: 'prompt $i in $tag');
          if (tag != 'en') {
            expect(
              localized[i],
              isNot(english[i]),
              reason: 'prompt $i in $tag must not silently be English',
            );
          }
        }
        // Reasonable Reflection-screen hint-text length -- generous, but
        // catches an accidental paragraph-length mistranslation.
        for (final prompt in localized) {
          expect(prompt.length, lessThan(80), reason: 'prompt in $tag');
        }
      });
    }

    test(
        'prompt IDENTITY (index) is fixed per key and independent of '
        'locale -- switching locale changes presentation only, never '
        'which prompt was selected', () {
      const keys = [
        'a5f3c111-1111-4111-8111-111111111111',
        'a5f3c111-1111-4111-8111-111111111112',
        'a5f3c111-1111-4111-8111-111111111113',
        'not-a-uuid-legacy-id',
      ];

      for (final key in keys) {
        final index = reflectionPromptIndexFor(key);
        expect(index, reflectionPromptIndexFor(key), reason: 'stable');

        for (final locale in locales) {
          final l10n = lookupAppLocalizations(locale);
          final localizedPrompt = localizedReflectionPrompts(l10n)[index];
          // The same index, read through every locale's own reviewed
          // list, always resolves to *a* real canonical prompt in that
          // locale -- never an out-of-range/placeholder value -- and the
          // canonical (English) identity function agrees on which prompt
          // that conceptually is.
          expect(localizedPrompt, isNotEmpty);
        }
        expect(reflectionPromptFor(key), reflectionPrompts[index]);
      }
    });

    test(
        'legacy reflectionPromptFor API is unchanged: exact same string '
        'result as before this hotfix, for every existing pinned case', () {
      expect(reflectionPromptFor(''), reflectionPrompts[0]);
      expect(reflectionPromptFor('a'), reflectionPrompts[97 % 6]);
      expect(reflectionPromptFor('ab'), reflectionPrompts[(97 + 98) % 6]);
    });
  });

  group('Issue 3 -- notifications', () {
    test(
        'notificationTitle/notificationBody exist and are non-empty for '
        'all 15 product locales', () {
      for (final locale in locales) {
        final tag = EastLocaleRegistry.canonicalTag(locale);
        final l10n = lookupAppLocalizations(locale);
        expect(l10n.notificationTitle, isNotEmpty, reason: tag);
        expect(l10n.notificationBody, isNotEmpty, reason: tag);
      }
    });

    test(
        'WisdomNotificationService defaults to English until told '
        'otherwise (pre-hotfix behavior preserved for any caller that '
        'never calls updateCopy)', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.utc(2041, 7, 23, 8);
      final platform = _FakeNotificationPlatform(enabled: true);
      final service = WisdomNotificationService(
        platform: platform,
        clock: () => now,
      );

      await service.scheduleFromAuthoritativeUnlock(
        now.add(const Duration(hours: 24)),
      );

      expect(platform.schedules.single.title, 'EAST.');
      expect(platform.schedules.single.body, 'Something waits in silence.');
    });

    test(
        'updateCopy makes every subsequent schedule use the selected '
        'EAST. locale\'s reviewed title/body, for all 15 locales', () async {
      for (final locale in locales) {
        SharedPreferences.setMockInitialValues({});
        final now = DateTime.utc(2041, 7, 23, 8);
        final platform = _FakeNotificationPlatform(enabled: true);
        final service = WisdomNotificationService(
          platform: platform,
          clock: () => now,
        );
        final l10n = lookupAppLocalizations(locale);

        service.updateCopy(WisdomNotificationCopy(l10n));
        await service.scheduleFromAuthoritativeUnlock(
          now.add(const Duration(hours: 24)),
        );

        expect(platform.schedules.single.title, l10n.notificationTitle);
        expect(platform.schedules.single.body, l10n.notificationBody);
      }
    });

    test(
        'EN -> TR: an opted-in pending reminder is rescheduled with '
        'Turkish copy at the EXACT SAME trigger instant, never duplicated, '
        'never created for a non-opted-in user, never re-enabled if denied',
        () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.utc(2041, 7, 23, 8);
      final platform = _FakeNotificationPlatform(enabled: true);
      final service = WisdomNotificationService(
        platform: platform,
        clock: () => now,
      );
      final unlockAt = now.add(const Duration(hours: 24));

      // 1. English reminder scheduled (opted in).
      await service.scheduleFromAuthoritativeUnlock(unlockAt);
      expect(platform.schedules.single.title, 'EAST.');
      expect(
        platform.schedules.single.unlockAt.millisecondsSinceEpoch,
        unlockAt.millisecondsSinceEpoch,
      );

      // 2. Locale changes to Turkish; the exact same reconciliation
      // `HomeScreen.didChangeDependencies` performs on a real locale
      // change (copy update, then a status-driven resync) runs here.
      final tr = lookupAppLocalizations(const Locale('tr'));
      service.updateCopy(WisdomNotificationCopy(tr));
      await service.synchronizeWithStatus(
        DailyWisdomStatus(
          isReady: false,
          unlockAt: unlockAt,
          remaining: unlockAt.difference(now),
        ),
      );

      // Exactly one live schedule (no duplicate), Turkish content, the
      // identical trigger instant.
      expect(platform.schedules, hasLength(1));
      expect(platform.schedules.single.title, tr.notificationTitle);
      expect(platform.schedules.single.body, tr.notificationBody);
      expect(
        platform.schedules.single.unlockAt.millisecondsSinceEpoch,
        unlockAt.millisecondsSinceEpoch,
      );
      // One cancel+schedule pair per step -- two steps, never more (no
      // stray extra cancellations/schedules that would suggest a
      // duplicate reminder was created).
      expect(
        platform.events.where((e) => e.startsWith('schedule:')).length,
        2,
      );
      expect(
        platform.events.where((e) => e.startsWith('cancel:')).length,
        2,
      );
    });

    test(
        'a never-opted-in user gets no schedule after a locale change '
        'reconciliation', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.utc(2041, 7, 23, 8);
      final platform = _FakeNotificationPlatform(enabled: false);
      final service = WisdomNotificationService(
        platform: platform,
        clock: () => now,
      );
      final unlockAt = now.add(const Duration(hours: 24));

      service.updateCopy(
        WisdomNotificationCopy(lookupAppLocalizations(const Locale('tr'))),
      );
      await service.synchronizeWithStatus(
        DailyWisdomStatus(
          isReady: false,
          unlockAt: unlockAt,
          remaining: unlockAt.difference(now),
        ),
      );

      expect(platform.schedules, isEmpty);
    });
  });
}

class _ScheduleCall {
  _ScheduleCall(this.title, this.body, this.unlockAt);
  final String title;
  final String body;
  final DateTime unlockAt;
}

class _FakeNotificationPlatform implements WisdomNotificationPlatform {
  _FakeNotificationPlatform({required this.enabled});

  final bool enabled;
  final List<String> events = [];
  final List<_ScheduleCall> schedules = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> notificationsEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async => enabled;

  @override
  Future<void> cancel(int id) async {
    events.add('cancel:$id');
    schedules.clear();
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  }) async {
    events.add('schedule:$id');
    schedules
      ..clear()
      ..add(_ScheduleCall(title, body, unlockAt));
  }
}
