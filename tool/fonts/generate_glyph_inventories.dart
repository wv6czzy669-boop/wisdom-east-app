import 'dart:convert';
import 'dart:io';

import 'package:wisdom_app/data/wisdoms_ar.dart';
import 'package:wisdom_app/data/wisdoms_ja.dart';
import 'package:wisdom_app/data/wisdoms_ko.dart';
import 'package:wisdom_app/data/wisdoms_th.dart';
import 'package:wisdom_app/data/wisdoms_zh_hant.dart';

/// Rebuilds deterministic controlled-copy glyph inventories for Phase 5B.
///
/// These inventories intentionally exclude arbitrary Reflection text. EAST.
/// ships full script fonts plus a cross-script fallback chain for user input;
/// narrowing that open-ended content to today's corpus would be unsafe.
void main() {
  const configurations = <_InventoryConfiguration>[
    _InventoryConfiguration(
      tag: 'ja',
      arbPath: 'lib/l10n/app_ja.arb',
      wisdoms: japaneseWisdomCatalog,
      nativeName: '日本語',
      supplemental: '年月日',
    ),
    _InventoryConfiguration(
      tag: 'ko',
      arbPath: 'lib/l10n/app_ko.arb',
      wisdoms: koreanWisdomCatalog,
      nativeName: '한국어',
      supplemental: '년월일',
    ),
    _InventoryConfiguration(
      tag: 'zh-Hant',
      arbPath: 'lib/l10n/app_zh_Hant.arb',
      wisdoms: traditionalChineseWisdomCatalog,
      nativeName: '繁體中文',
      supplemental: '年月日',
    ),
    _InventoryConfiguration(
      tag: 'ar',
      arbPath: 'lib/l10n/app_ar.arb',
      wisdoms: arabicWisdomCatalog,
      nativeName: 'العربية',
      supplemental: '٠١٢٣٤٥٦٧٨٩',
    ),
    _InventoryConfiguration(
      tag: 'th',
      arbPath: 'lib/l10n/app_th.arb',
      wisdoms: thaiWisdomCatalog,
      nativeName: 'ไทย',
      supplemental: '๐๑๒๓๔๕๖๗๘๙',
    ),
  ];

  const fixedRenderedCopy = 'EAST. 0123456789 '
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz '
      '.,:;!?…—–-+/()[]{}%&@#|“”‘’\'"\n';

  final outputDirectory = Directory('assets/fonts/glyphs')
    ..createSync(
      recursive: true,
    );
  for (final configuration in configurations) {
    final arb = jsonDecode(File(configuration.arbPath).readAsStringSync())
        as Map<String, dynamic>;
    final controlledText = <String>[
      fixedRenderedCopy,
      configuration.nativeName,
      configuration.supplemental,
      ...configuration.wisdoms.values,
      ...arb.entries
          .where((entry) => !entry.key.startsWith('@'))
          .map((entry) => entry.value)
          .whereType<String>(),
    ].join('\n');
    final runes = controlledText.runes.toSet().toList()..sort();
    File('${outputDirectory.path}/${configuration.tag}.txt')
        .writeAsStringSync('${String.fromCharCodes(runes)}\n');
  }
}

class _InventoryConfiguration {
  const _InventoryConfiguration({
    required this.tag,
    required this.arbPath,
    required this.wisdoms,
    required this.nativeName,
    required this.supplemental,
  });

  final String tag;
  final String arbPath;
  final Map<String, String> wisdoms;
  final String nativeName;
  final String supplemental;
}
