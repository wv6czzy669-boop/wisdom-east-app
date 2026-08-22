import 'package:flutter/widgets.dart';

import '../persistence/storage_preferences_adapter.dart';

/// Owns EAST.'s explicit locale override.
///
/// A `null` [explicitLocale] is the durable System Default sentinel. An
/// override is stored as a canonical BCP-47 tag, rather than a bare language
/// code, so future translated locales such as `zh-Hant` and `pt-BR` do not
/// require a preference migration.
class LocalePreferenceController extends ChangeNotifier {
  LocalePreferenceController({
    StoragePreferencesAdapter? storage,
    List<Locale> supportedLocales = const <Locale>[Locale('en')],
  })  : _storage = storage ?? StoragePreferencesAdapter(),
        _supportedLocales = List<Locale>.unmodifiable(supportedLocales);

  static const String preferenceKey = 'east_locale_preference';

  final StoragePreferencesAdapter _storage;
  final List<Locale> _supportedLocales;

  Locale? _explicitLocale;
  Future<void>? _loadFuture;
  bool _changedDuringLoad = false;

  /// `null` means follow the system language when it is supported.
  Locale? get explicitLocale => _explicitLocale;

  bool get isSystemDefault => _explicitLocale == null;

  /// Restores the saved override once, safely treating malformed and
  /// currently unsupported values as System Default.
  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    String? rawTag;
    try {
      rawTag = await _storage.getString(preferenceKey);
    } catch (_) {
      // A locale preference must never block application startup.
      return;
    }

    if (_changedDuringLoad) return;

    final parsed = parseBcp47Tag(rawTag);
    final resolved = parsed != null && _isSupported(parsed) ? parsed : null;
    if (_sameLocale(_explicitLocale, resolved)) return;

    _explicitLocale = resolved;
    notifyListeners();
  }

  /// Applies an override immediately, then persists it without allowing a
  /// storage failure to interrupt the active session. Passing `null` returns
  /// to System Default and removes the durable override.
  Future<void> setExplicitLocale(Locale? locale) async {
    _changedDuringLoad = true;
    final normalized =
        locale == null ? null : parseBcp47Tag(toBcp47Tag(locale));
    final next =
        normalized != null && _isSupported(normalized) ? normalized : null;

    if (!_sameLocale(_explicitLocale, next)) {
      _explicitLocale = next;
      notifyListeners();
    }

    try {
      if (next == null) {
        await _storage.remove(preferenceKey);
      } else {
        await _storage.setString(preferenceKey, toBcp47Tag(next));
      }
    } catch (_) {
      // The in-memory choice remains stable for this session. A future
      // launch simply falls back to the safely readable stored value.
    }
  }

  bool _isSupported(Locale locale) {
    return _supportedLocales.any((candidate) => _sameLocale(candidate, locale));
  }

  /// Converts a Flutter [Locale] to its canonical BCP-47-compatible tag.
  static String toBcp47Tag(Locale locale) {
    final language = locale.languageCode.toLowerCase();
    final script = locale.scriptCode;
    final region = locale.countryCode;
    return <String>[
      language,
      if (script != null && script.isNotEmpty)
        '${script[0].toUpperCase()}${script.substring(1).toLowerCase()}',
      if (region != null && region.isNotEmpty) region.toUpperCase(),
    ].join('-');
  }

  /// Parses only the language-script-region form EAST. needs today while
  /// retaining correct script/region structure for future supported locales.
  static Locale? parseBcp47Tag(String? rawTag) {
    if (rawTag == null || rawTag.isEmpty) return null;
    final subtags = rawTag.split('-');
    if (subtags.isEmpty ||
        !RegExp(r'^[A-Za-z]{2,8}$').hasMatch(subtags.first)) {
      return null;
    }

    String? script;
    String? region;
    for (final subtag in subtags.skip(1)) {
      if (script == null && RegExp(r'^[A-Za-z]{4}$').hasMatch(subtag)) {
        script =
            '${subtag[0].toUpperCase()}${subtag.substring(1).toLowerCase()}';
      } else if (region == null &&
          (RegExp(r'^[A-Za-z]{2}$').hasMatch(subtag) ||
              RegExp(r'^\d{3}$').hasMatch(subtag))) {
        region = subtag.toUpperCase();
      } else {
        return null;
      }
    }

    return Locale.fromSubtags(
      languageCode: subtags.first.toLowerCase(),
      scriptCode: script,
      countryCode: region,
    );
  }

  /// Resolves System Default against the locales actually translated by this
  /// build. Exact script/region matches win, then a matching language, then
  /// English's current first-supported fallback.
  static Locale resolveSystemLocale(
    Locale? deviceLocale,
    Iterable<Locale> supportedLocales,
  ) {
    final supported = supportedLocales.toList(growable: false);
    assert(supported.isNotEmpty, 'EAST. must always support English.');
    if (supported.isEmpty) return const Locale('en');
    if (deviceLocale == null) return supported.first;

    for (final candidate in supported) {
      if (_sameLocale(candidate, deviceLocale)) return candidate;
    }
    for (final candidate in supported) {
      if (candidate.languageCode.toLowerCase() ==
          deviceLocale.languageCode.toLowerCase()) {
        return candidate;
      }
    }
    return supported.first;
  }

  static bool _sameLocale(Locale? first, Locale? second) {
    if (first == null || second == null) return first == second;
    return toBcp47Tag(first) == toBcp47Tag(second);
  }
}
