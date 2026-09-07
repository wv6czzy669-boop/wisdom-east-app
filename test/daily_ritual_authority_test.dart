import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/daily_wisdom_selection.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/daily_ritual_authority.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';

import 'persistence_test_helpers.dart';

final _now = DateTime.utc(2026, 9, 6, 12);
final _scope = 'a' * 64;
const _id = '11111111-2222-4333-8444-555555555555';

Map<String, Object?> _payload({bool created = true}) => {
      'wisdomId': 'east_wisdom_0059',
      'revealId': _id,
      'revealedAtMs': _now.millisecondsSinceEpoch,
      'unlockAtMs': _now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
      'accountScope': _scope,
      'created': created,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'authorization decodes public catalog identity without trusting server text',
      () {
    final grant = AuthorizedDailyRitual.decode(
        {..._payload(), 'text': 'Untrusted server text'});
    expect(grant.record.text, 'Peace enters slowly.');
    expect(grant.record.revealId, _id);
    expect(grant.record.authorityAccountScope, _scope);
  });

  for (final invalid in [
    {'wisdomId': 'unknown'},
    {'revealId': 'not-a-uuid'},
    {'accountScope': 'raw account'},
    {'unlockAtMs': 42},
    {'revealedAtMs': -1},
    {'created': 'true'},
  ]) {
    test('invalid authorization fails closed: ${invalid.keys.single}', () {
      expect(() => AuthorizedDailyRitual.decode({..._payload(), ...invalid}),
          throwsFormatException);
    });
  }

  test('preparing a widget candidate never acquires the daily right', () async {
    final graph = DailyAccessTestGraph();
    final authority = _Authority();
    final service = DailyWisdomAccessService(
        repository: graph.repository, authority: authority, clock: () => _now);
    final prepared = await _prepare(service);
    expect(prepared.hasAuthoritativeRecord, isFalse);
    expect(authority.claims, 0);
    expect(await graph.repository.loadDailyWisdomRecord(), isNull);
  });

  test('two independent device stores adopt the same server occurrence',
      () async {
    final authority = _Authority();
    final a = DailyAccessTestGraph(adapter: _MemoryPreferences());
    final b = DailyAccessTestGraph(adapter: _MemoryPreferences());
    final first = DailyWisdomAccessService(
        repository: a.repository, authority: authority, clock: () => _now);
    final second = DailyWisdomAccessService(
        repository: b.repository, authority: authority, clock: () => _now);
    final firstAccess =
        await first.authorizePreparedReveal(await _prepare(first));
    final secondAccess =
        await second.authorizePreparedReveal(await _prepare(second));
    expect(firstAccess.isNew, isTrue);
    expect(secondAccess.isNew, isFalse);
    expect(firstAccess.revealId, secondAccess.revealId);
    expect(firstAccess.text, secondAccess.text);
    expect(firstAccess.unlockAt, secondAccess.unlockAt);
    expect((await a.repository.loadDailyWisdomRecord())!.encode(),
        (await b.repository.loadDailyWisdomRecord())!.encode());
  });

  test('offline authorization leaves the candidate unshown and uncommitted',
      () async {
    final graph = DailyAccessTestGraph();
    final authority = _Authority()..offline = true;
    final service = DailyWisdomAccessService(
        repository: graph.repository, authority: authority, clock: () => _now);
    final prepared = await _prepare(service);
    await expectLater(service.authorizePreparedReveal(prepared),
        throwsA(isA<DailyRitualAuthorityException>()));
    expect(await graph.repository.loadDailyWisdomRecord(), isNull);
    expect((await graph.repository.loadPendingDailyWisdomReveal())!.phase,
        PendingDailyWisdomRevealPhase.prepared);
  });

  test(
      'cached authorized wisdom remains readable offline without claiming again',
      () async {
    final graph = DailyAccessTestGraph();
    final authority = _Authority()..offline = true;
    final service = DailyWisdomAccessService(
        repository: graph.repository, authority: authority, clock: () => _now);
    await service.reconcileAccountAuthority();
    final status = await service.status();
    expect(status.isReady, isFalse);
    expect(status.lockedText, 'Peace enters slowly.');
    expect(status.revealId, _id);
    expect(authority.claims, 0);
  });

  test('an expired offline cache never authorizes a new wisdom', () async {
    final graph = DailyAccessTestGraph();
    final authority = _Authority()..offline = true;
    final service = DailyWisdomAccessService(
        repository: graph.repository,
        authority: authority,
        clock: () => _now.add(const Duration(hours: 25)));
    await service.reconcileAccountAuthority();
    await expectLater(
        service.reveal(
            selectWisdom: () => 'Peace enters slowly.',
            selectWisdomWithIdentity: () => DailyWisdomSelection(
                text: 'Peace enters slowly.', wisdomId: 'east_wisdom_0059')),
        throwsA(isA<DailyRitualAuthorityException>()));
    expect((await graph.repository.loadDailyWisdomRecord())!.revealId, _id);
  });

  test('late refresh cannot replace a newer grant for the same account',
      () async {
    final graph = DailyAccessTestGraph();
    final old = AuthorizedDailyRitual.decode(_payload()).record;
    final next = DailyWisdomRecord(
        text: old.text,
        wisdomId: old.wisdomId,
        revealId: '22222222-2222-4333-8444-555555555555',
        revealedAt: old.revealedAt.add(const Duration(hours: 24)),
        unlockAt: old.unlockAt.add(const Duration(hours: 24)),
        authorityAccountScope: _scope);
    await graph.repository.adoptAuthorizedRecord(next);
    final result = await graph.repository.adoptAuthorizedRecord(old);
    expect(result.revealId, next.revealId);
    expect((await graph.repository.loadDailyWisdomRecord())!.revealId,
        next.revealId);
  });

  test(
      'account provenance survives serialization and identity-preserving copies',
      () {
    final record = AuthorizedDailyRitual.decode(_payload()).record;
    expect(DailyWisdomRecord.decode(record.encode()).authorityAccountScope,
        _scope);
    expect(record.copyWith(wisdomId: record.wisdomId).authorityAccountScope,
        _scope);
  });

  test(
      'the native claim sends no wisdom text, question, Kept or Reflection content',
      () async {
    const authority = MethodChannelDailyRitualAuthority();
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authority.channel, (call) async {
      captured = call;
      return _payload();
    });
    await authority.claim(wisdomId: 'east_wisdom_0059');
    expect(captured!.method, 'claim');
    expect(captured!.arguments, {'wisdomId': 'east_wisdom_0059'});
  });
}

Future<DailyWisdomPreparedReveal> _prepare(DailyWisdomAccessService service) =>
    service.prepareReveal(
      selectWisdom: () => 'Peace enters slowly.',
      selectWisdomWithIdentity: () => DailyWisdomSelection(
          text: 'Peace enters slowly.', wisdomId: 'east_wisdom_0059'),
    );

class _Authority implements DailyRitualAuthority {
  bool offline = false;
  int claims = 0;
  @override
  Future<AuthorizedDailyRitual> claim(
      {required String wisdomId, DailyWisdomRecord? legacyRecord}) async {
    if (offline) {
      throw const DailyRitualAuthorityException(
          DailyRitualAuthorityFailure.connectionRequired);
    }
    claims++;
    return AuthorizedDailyRitual.decode(_payload(created: claims == 1));
  }

  @override
  Future<AuthorizedDailyRitual?> readCached() async =>
      AuthorizedDailyRitual.decode(_payload(created: false));
  @override
  Future<AuthorizedDailyRitual?> refresh(
      {DailyWisdomRecord? legacyRecord}) async {
    if (offline) {
      throw const DailyRitualAuthorityException(
          DailyRitualAuthorityFailure.connectionRequired);
    }
    return readCached();
  }
}

class _MemoryPreferences extends StoragePreferencesAdapter {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);
}
