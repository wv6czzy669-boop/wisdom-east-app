import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/stored_favorite_entry_codec.dart';

void main() {
  test('current-schema JSON produces the same FavoriteItem Build 25 would', () {
    final item = FavoriteItem(
      id: 'explicit-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Kept text.',
      reflection: 'A reflection.',
      reflectedAt: '2026-01-02T09:00:00.000Z',
    );
    final raw = item.encode();

    final decoded = StoredFavoriteEntryCodec.decode(raw, index: 0);

    expect(decoded, isNotNull);
    expect(decoded!.item.id, 'explicit-1');
    expect(decoded.item.text, 'Kept text.');
    expect(decoded.item.date, '2026-01-01T09:00:00.000Z');
    expect(decoded.item.reflection, 'A reflection.');
    expect(decoded.item.reflectedAt, '2026-01-02T09:00:00.000Z');
    // Canonical current-schema encoding round-trips exactly, so no
    // re-persistence is required.
    expect(decoded.requiresMigration, isFalse);
  });

  test('legacy pipe input produces the same FavoriteItem Build 25 would', () {
    const raw = '2026-01-01T09:00:00.000Z|||Pipe-format text.';

    final decoded = StoredFavoriteEntryCodec.decode(raw, index: 3);

    expect(decoded, isNotNull);
    expect(decoded!.item.date, '2026-01-01T09:00:00.000Z');
    expect(decoded.item.text, 'Pipe-format text.');
    expect(decoded.item.reflection, isNull);
    // Legacy pipe format always requires migration to current-schema JSON.
    expect(decoded.requiresMigration, isTrue);
  });

  test(
      'an entry missing an explicit ID receives the exact Build 25 fallback '
      'ID: legacy-v1-<index>-<stable hash of the raw entry>', () {
    const raw = '2026-01-01T09:00:00.000Z|||No id here.';

    final decoded = StoredFavoriteEntryCodec.decode(raw, index: 5);

    expect(decoded, isNotNull);
    final expectedHash = StoredFavoriteEntryCodec.stableHashFor(raw);
    expect(decoded!.item.id, 'legacy-v1-5-$expectedHash');
    expect(
      decoded.item.id,
      StoredFavoriteEntryCodec.fallbackIdFor(raw: raw, index: 5),
    );
  });

  test('a current-schema entry with no id key also receives the fallback ID',
      () {
    const raw = '{"schemaVersion":2,"date":"2026-01-01T09:00:00.000Z",'
        '"text":"No id in JSON."}';

    final decoded = StoredFavoriteEntryCodec.decode(raw, index: 2);

    expect(decoded, isNotNull);
    expect(
      decoded!.item.id,
      StoredFavoriteEntryCodec.fallbackIdFor(raw: raw, index: 2),
    );
  });

  // Fallback identity is `legacy-v1-<index>-<stableHash(raw)>` — Build 25's
  // exact algorithm, deliberately dependent on BOTH the raw entry and its
  // StringList index. It is not, and must never become, order-independent:
  // moving an entry to a different list position is a different index and
  // therefore a different fallback ID. The following tests prove the real
  // dependency on both inputs, not independence from either.

  test('1. same raw + same index produces the same fallback ID repeatedly', () {
    const raw = '2026-01-01T09:00:00.000Z|||Stable text.';

    final first = StoredFavoriteEntryCodec.decode(raw, index: 7);
    final second = StoredFavoriteEntryCodec.decode(raw, index: 7);

    expect(first!.item.id, second!.item.id);
    expect(first.item.id,
        StoredFavoriteEntryCodec.fallbackIdFor(raw: raw, index: 7));
  });

  test('2. same raw + a different index produces a different fallback ID', () {
    const raw = '2026-01-01T09:00:00.000Z|||Same content, moved.';

    final atIndex0 = StoredFavoriteEntryCodec.decode(raw, index: 0)!.item.id;
    final atIndex1 = StoredFavoriteEntryCodec.decode(raw, index: 1)!.item.id;

    expect(atIndex0, isNot(atIndex1));
    expect(
        atIndex0, StoredFavoriteEntryCodec.fallbackIdFor(raw: raw, index: 0));
    expect(
        atIndex1, StoredFavoriteEntryCodec.fallbackIdFor(raw: raw, index: 1));
  });

  test('3. different raw + the same index produces a different fallback ID',
      () {
    const rawA = '2026-01-01T09:00:00.000Z|||Entry A.';
    const rawB = '2026-01-01T09:00:00.000Z|||Entry B.';

    final idA = StoredFavoriteEntryCodec.decode(rawA, index: 4)!.item.id;
    final idB = StoredFavoriteEntryCodec.decode(rawB, index: 4)!.item.id;

    expect(idA, isNot(idB));
  });

  test(
      '4. the produced ID exactly matches '
      'legacy-v1-<index>-<stableHashFor(raw)>', () {
    const raw = '2026-01-01T09:00:00.000Z|||Exact-shape check.';
    const index = 9;

    final decoded = StoredFavoriteEntryCodec.decode(raw, index: index)!;

    expect(
      decoded.item.id,
      'legacy-v1-$index-${StoredFavoriteEntryCodec.stableHashFor(raw)}',
    );
  });

  test('malformed entries are rejected exactly as Build 25 rejects them', () {
    expect(StoredFavoriteEntryCodec.decode('', index: 0), isNull);
    expect(
      StoredFavoriteEntryCodec.decode('no pipe separator at all', index: 0),
      isNull,
    );
    expect(
      StoredFavoriteEntryCodec.decode('{"not":"a valid favorite"}', index: 0),
      isNull,
    );
    expect(
      StoredFavoriteEntryCodec.decode('   |||   ', index: 0),
      isNull,
    );
  });

  test('the stable hash function is deterministic and content-sensitive', () {
    expect(
      StoredFavoriteEntryCodec.stableHashFor('a'),
      StoredFavoriteEntryCodec.stableHashFor('a'),
    );
    expect(
      StoredFavoriteEntryCodec.stableHashFor('a'),
      isNot(StoredFavoriteEntryCodec.stableHashFor('b')),
    );
  });
}
