/// Pure, on-device matching for Kept's editorial search field.
///
/// The matcher owns no state and never persists or transmits a query. It
/// applies conservative Unicode-friendly folding for the product's Latin
/// locales, Turkish dotted/dotless I, decomposed combining marks, and Arabic
/// vocalization marks, while leaving CJK and other scripts intact.
abstract final class KeptSearchMatcher {
  static bool matches({
    required String wisdom,
    required String? reflection,
    required String query,
  }) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) return true;

    final corpus = normalize('$wisdom ${reflection ?? ''}');
    return normalizedQuery.split(' ').every(corpus.contains);
  }

  static String normalize(String value) {
    var normalized = value
        .replaceAll('İ', 'i')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(
            RegExp(r'[\u0610-\u061A\u0640\u064B-\u065F\u0670\u06D6-\u06ED]'),
            '');

    for (final entry in _folds.entries) {
      for (final rune in entry.value.runes) {
        normalized =
            normalized.replaceAll(String.fromCharCode(rune), entry.key);
      }
    }

    return normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const Map<String, String> _folds = {
    'a': 'àáâãäåāăąǎǟǡǻȁȃȧạảấầẩẫậắằẳẵặ',
    'ae': 'æǽǣ',
    'c': 'çćĉċč',
    'd': 'ďđð',
    'e': 'èéêëēĕėęěȅȇẹẻẽếềểễệ',
    'g': 'ĝğġģǧǵ',
    'h': 'ĥħȟ',
    'i': 'ìíîïĩīĭįǐȉȋỉị',
    'j': 'ĵǰ',
    'k': 'ķǩ',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉŋǹ',
    'o': 'òóôõöøōŏőǒǫǭǿȍȏȯọỏốồổỗộớờởỡợ',
    'oe': 'œ',
    'r': 'ŕŗřȑȓ',
    's': 'śŝşšș',
    'ss': 'ß',
    't': 'ţťŧț',
    'th': 'þ',
    'u': 'ùúûüũūŭůűųǔǖǘǚǜȕȗụủứừửữự',
    'w': 'ŵẁẃẅ',
    'y': 'ýÿŷỳỵỷỹ',
    'z': 'źżž',
  };
}
