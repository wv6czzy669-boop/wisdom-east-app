import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';

void main() {
  // Fixed fixtures only — no random UUID generation in pure serialization
  // tests.
  const revealIdA = '123e4567-e89b-42d3-a456-426614174000';
  const revealIdB = '223e4567-e89b-42d3-a456-426614174001';
  const mutationIdA = 'a1b2c3d4-0000-4000-8000-000000000001';
  const mutationIdB = 'a1b2c3d4-0000-4000-8000-000000000002';

  final revealedAt = DateTime.utc(2026, 6, 18, 9, 30);
  final keptAt = DateTime.utc(2026, 6, 18, 9, 31);
  final updatedAt = DateTime.utc(2026, 6, 18, 9, 31);

  KeptRecord buildRecord({
    required String id,
    required String revealId,
    String wisdomText = 'What is meant for you does not panic.',
    String mutationId = mutationIdA,
  }) {
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt,
      keptAt: keptAt,
      updatedAt: updatedAt,
      mutationId: mutationId,
    );
  }

  test('empty envelope round-trips through encode/decode', () {
    final envelope = KeptStateEnvelope();

    final decoded = KeptStateEnvelope.decode(envelope.encode());

    expect(decoded.activeRecords, isEmpty);
    expect(decoded, envelope);
  });

  test('multi-record envelope round-trips preserving exact order', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final second = buildRecord(
      id: 'kept-2',
      revealId: revealIdB,
      mutationId: mutationIdB,
    );
    final envelope = KeptStateEnvelope(activeRecords: [first, second]);

    final decoded = KeptStateEnvelope.decode(envelope.encode());

    expect(
        decoded.activeRecords.map((r) => r.id).toList(), ['kept-1', 'kept-2']);
    expect(decoded, envelope);
  });

  test('duplicate wisdomText with different ids/revealIds is accepted', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final second = buildRecord(
      id: 'kept-2',
      revealId: revealIdB,
      mutationId: mutationIdB,
    );

    expect(
      () => KeptStateEnvelope(activeRecords: [first, second]),
      returnsNormally,
    );
    final envelope = KeptStateEnvelope(activeRecords: [first, second]);
    expect(envelope.activeRecords[0].wisdomText,
        envelope.activeRecords[1].wisdomText);
  });

  test('duplicate record id is rejected', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final duplicateId = buildRecord(
      id: 'kept-1',
      revealId: revealIdB,
      mutationId: mutationIdB,
    );

    expect(
      () => KeptStateEnvelope(activeRecords: [first, duplicateId]),
      throwsFormatException,
    );
  });

  test('duplicate revealId is rejected', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final duplicateRevealId = buildRecord(
      id: 'kept-2',
      revealId: revealIdA,
      mutationId: mutationIdB,
    );

    expect(
      () => KeptStateEnvelope(activeRecords: [first, duplicateRevealId]),
      throwsFormatException,
    );
  });

  test('missing activeRecords is rejected on decode', () {
    final map = KeptStateEnvelope().encode();
    map.remove('activeRecords');

    expect(() => KeptStateEnvelope.decode(map), throwsFormatException);
  });

  test('malformed activeRecords (not a list) is rejected on decode', () {
    final map = KeptStateEnvelope().encode();
    map['activeRecords'] = 'not-a-list';

    expect(() => KeptStateEnvelope.decode(map), throwsFormatException);
  });

  test('unsupported envelope schema version is rejected on decode', () {
    final map = KeptStateEnvelope().encode();
    map['schemaVersion'] = 2;

    expect(() => KeptStateEnvelope.decode(map), throwsFormatException);
  });

  test('malformed nested KeptRecord is rejected on decode', () {
    final record = buildRecord(id: 'kept-1', revealId: revealIdA);
    final envelope = KeptStateEnvelope(activeRecords: [record]);
    final map = envelope.encode();
    (map['activeRecords'] as List)
        .cast<Map<String, dynamic>>()
        .first
        .remove('wisdomText');

    expect(() => KeptStateEnvelope.decode(map), throwsFormatException);
  });

  test('unknown top-level key is ignored on decode', () {
    final record = buildRecord(id: 'kept-1', revealId: revealIdA);
    final envelope = KeptStateEnvelope(activeRecords: [record]);
    final map = envelope.encode();
    map['dataEpoch'] = 'reserved-for-a-later-phase';

    expect(() => KeptStateEnvelope.decode(map), returnsNormally);
    expect(KeptStateEnvelope.decode(map), envelope);
  });

  test('activeRecords cannot be externally mutated', () {
    final record = buildRecord(id: 'kept-1', revealId: revealIdA);
    final envelope = KeptStateEnvelope(activeRecords: [record]);

    expect(
      () => envelope.activeRecords.add(
        buildRecord(id: 'kept-2', revealId: revealIdB),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => envelope.activeRecords.removeAt(0),
      throwsUnsupportedError,
    );
  });

  test('copyWith replaces activeRecords without mutating the original', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final second = buildRecord(
      id: 'kept-2',
      revealId: revealIdB,
      mutationId: mutationIdB,
    );
    final original = KeptStateEnvelope(activeRecords: [first]);

    final updated = original.copyWith(activeRecords: [first, second]);

    expect(original.activeRecords, [first]);
    expect(updated.activeRecords, [first, second]);
  });

  test(
      'value equality and hashCode are based on record contents, not '
      'identity', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final second = buildRecord(
      id: 'kept-2',
      revealId: revealIdB,
      mutationId: mutationIdB,
    );

    final envelopeA = KeptStateEnvelope(activeRecords: [first, second]);
    final envelopeB = KeptStateEnvelope(
      activeRecords: [
        buildRecord(id: 'kept-1', revealId: revealIdA),
        buildRecord(id: 'kept-2', revealId: revealIdB, mutationId: mutationIdB),
      ],
    );
    final envelopeDifferentOrder = KeptStateEnvelope(
      activeRecords: [second, first],
    );

    expect(envelopeA, envelopeB);
    expect(envelopeA.hashCode, envelopeB.hashCode);
    expect(envelopeA, isNot(envelopeDifferentOrder));
  });

  test('encode/encodeString and decode/decodeString round-trip exactly', () {
    final first = buildRecord(id: 'kept-1', revealId: revealIdA);
    final second = buildRecord(
      id: 'kept-2',
      revealId: revealIdB,
      mutationId: mutationIdB,
    );
    final envelope = KeptStateEnvelope(activeRecords: [first, second]);

    final encoded = envelope.encode();
    expect(encoded['schemaVersion'], 3);
    expect(encoded['activeRecords'], isA<List>());
    expect((encoded['activeRecords'] as List).length, 2);

    final roundTripped =
        KeptStateEnvelope.decodeString(envelope.encodeString());
    expect(roundTripped, envelope);
  });
}
