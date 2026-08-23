import 'wisdoms_ar.dart';
import 'wisdoms_de.dart';
import 'wisdoms_es.dart';
import 'wisdoms_fr.dart';
import 'wisdoms_it.dart';
import 'wisdoms_ja.dart';
import 'wisdoms_ko.dart';
import 'wisdoms_nl.dart';
import 'wisdoms_pl.dart';
import 'wisdoms_pt_br.dart';
import 'wisdoms_th.dart';
import 'wisdoms_tr.dart';
import 'wisdoms_vi.dart';
import 'wisdoms_zh_hant.dart';

/// Reviewed wisdom presentation catalogs keyed by canonical BCP-47 tag.
///
/// Presence here does not make a locale runtime-supported or user-selectable.
const Map<String, Map<String, String>> reviewedLocalizedWisdomCatalogs =
    <String, Map<String, String>>{
  'tr': turkishWisdomCatalog,
  'ja': japaneseWisdomCatalog,
  'de': germanWisdomCatalog,
  'fr': frenchWisdomCatalog,
  'ko': koreanWisdomCatalog,
  'zh-Hant': traditionalChineseWisdomCatalog,
  'ar': arabicWisdomCatalog,
  'es': spanishWisdomCatalog,
  'pt-BR': brazilianPortugueseWisdomCatalog,
  'it': italianWisdomCatalog,
  'th': thaiWisdomCatalog,
  'nl': dutchWisdomCatalog,
  'pl': polishWisdomCatalog,
  'vi': vietnameseWisdomCatalog,
};
