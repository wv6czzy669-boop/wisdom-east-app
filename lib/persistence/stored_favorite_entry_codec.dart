import '../models/favorite_item.dart';

/// The outcome of successfully decoding one Build 25 stored entry: the
/// resulting [FavoriteItem], and whether its canonical re-encoded form now
/// differs from what was actually stored — meaning a caller that owns the
/// underlying stored list should persist the upgraded form.
class StoredFavoriteEntryDecodeResult {
  const StoredFavoriteEntryDecodeResult({
    required this.item,
    required this.requiresMigration,
  });

  final FavoriteItem item;
  final bool requiresMigration;
}

/// The exact Build 25 stored-entry decoding and fallback-identity
/// algorithm.
///
/// This is a narrow extraction of logic that used to live only inside
/// `SavedReflectionsService` (`_decodeEntry`/`_decodeCurrentEntry`/
/// `_legacyIdFor`/`_stableHash`) — moved here, unchanged, so both
/// `SavedReflectionsService` and the Build 26 Kept-storage migration engine
/// share one implementation instead of the migration engine inventing a
/// second, different fallback-identity scheme.
///
/// Deliberately knows nothing about SharedPreferences or migration state:
/// it is a pure function from one raw stored string (and the position it
/// occupied in whatever list it came from, which the fallback-identity
/// algorithm itself requires) to the same [FavoriteItem] Build 25 would
/// have produced, or the same failure outcome (`null`, never a thrown
/// exception).
abstract final class StoredFavoriteEntryCodec {
  /// Decodes one raw stored entry: current-schema JSON first, falling back
  /// to legacy pipe format, exactly as Build 25 always has. Returns `null`
  /// on any failure — this never throws.
  static StoredFavoriteEntryDecodeResult? decode(
    String raw, {
    required int index,
  }) {
    try {
      if (FavoriteItem.looksLikeCurrentSchema(raw)) {
        return _decodeCurrent(raw, index: index);
      }

      final item = FavoriteItem.decodeLegacy(
        raw,
        id: fallbackIdFor(raw: raw, index: index),
      );
      return StoredFavoriteEntryDecodeResult(
        item: item,
        requiresMigration: true,
      );
    } catch (_) {
      return null;
    }
  }

  static StoredFavoriteEntryDecodeResult? _decodeCurrent(
    String raw, {
    required int index,
  }) {
    try {
      final item = FavoriteItem.decodeCurrent(
        raw,
        fallbackId: fallbackIdFor(raw: raw, index: index),
      );
      return StoredFavoriteEntryDecodeResult(
        item: item,
        requiresMigration: item.encode() != raw,
      );
    } catch (_) {
      return null;
    }
  }

  /// The exact Build 25 fallback identity assigned to a stored entry with
  /// no explicit id: `legacy-v1-<index>-<stable hash of the raw string>`.
  /// Depends on both the entry's raw content and its position in the list
  /// it was read from — never on wisdom text or date alone, and never a
  /// newly invented scheme.
  static String fallbackIdFor({required String raw, required int index}) {
    return 'legacy-v1-$index-${stableHashFor(raw)}';
  }

  /// The same stable content hash Build 25 uses for both the fallback
  /// identity above and `SavedReflectionsService`'s own duplicate-id
  /// resolution — exposed so callers needing that exact algorithm never
  /// maintain a second copy of it.
  static String stableHashFor(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
