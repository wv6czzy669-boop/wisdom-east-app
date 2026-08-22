import 'package:flutter/widgets.dart';

import '../data/localized_wisdoms.dart';
import '../data/wisdoms.dart';
import '../localization/east_locale_registry.dart';

/// Read-only future contract: locale changes resolve presentation only and
/// never select, reveal, save, or otherwise create a wisdom occurrence.
class WisdomLocalizationResolver {
  const WisdomLocalizationResolver({
    this.localizedCatalog = reviewedLocalizedWisdomCatalogs,
  });

  /// Future reviewed entries keyed by canonical BCP-47 tag then wisdom ID.
  final Map<String, Map<String, String>> localizedCatalog;

  String? resolve({
    required String? wisdomId,
    required Locale locale,
    required String? persistedSnapshot,
  }) {
    final tag = EastLocaleRegistry.canonicalTag(locale);
    final localized =
        wisdomId == null ? null : localizedCatalog[tag]?[wisdomId];
    if (localized != null) return localized;
    final canonical = wisdomId == null ? null : _englishForId(wisdomId);
    return canonical ?? persistedSnapshot;
  }

  String? _englishForId(String wisdomId) {
    for (final wisdom in wisdoms) {
      if (wisdom['id'] == wisdomId) return wisdom['text'] as String;
    }
    return null;
  }
}
