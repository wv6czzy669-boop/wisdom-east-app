import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/appearance_preference_controller.dart';
import 'package:wisdom_app/services/keeper_ritual_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(KeeperRitualWidgetService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads and defensively decodes the complete native snapshot', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readKeeperRitualSnapshot');
      return <String, Object?>{
        'isKeeper': true,
        'state': 'revealed',
        'candidate': <String, Object?>{
          'candidateId': 'east_wisdom_0002:20',
          'canonicalText': 'Next.',
          'displayText': 'Sıradaki.',
          'wisdomId': 'east_wisdom_0002',
          'preparedAtMillis': 10,
          'activationAtMillis': 20,
        },
        'reveal': <String, Object?>{
          'candidateId': 'east_wisdom_0001:1',
          'canonicalText': 'Stay.',
          'displayText': 'Kal.',
          'wisdomId': 'east_wisdom_0001',
          'revealedAtMillis': 1000,
          'unlockAtMillis': 86401000,
          'needsAppCommit': true,
          'revealId': null,
        },
      };
    });

    final snapshot = await KeeperRitualWidgetService().readSnapshot();

    expect(snapshot, isNotNull);
    expect(snapshot!.isKeeper, isTrue);
    expect(snapshot.state, 'revealed');
    expect(snapshot.candidate!.wisdomId, 'east_wisdom_0002');
    expect(snapshot.candidate!.displayText, 'Sıradaki.');
    expect(snapshot.reveal!.wisdomId, 'east_wisdom_0001');
    expect(snapshot.reveal!.needsAppCommit, isTrue);
    expect(
      snapshot.reveal!.revealedAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
  });

  test('malformed snapshot and native failures fail closed to null', () async {
    messenger.setMockMethodCallHandler(channel,
        (_) async => <String, Object?>{'isKeeper': 'yes', 'state': 'pause'});
    expect(await KeeperRitualWidgetService().readSnapshot(), isNull);

    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await KeeperRitualWidgetService().readSnapshot(), isNull);
  });

  test('setKeeperEntitlement sends only the entitlement bit', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    expect(
      await KeeperRitualWidgetService().setKeeperEntitlement(true),
      isTrue,
    );
    expect(captured!.method, 'setKeeperEntitlement');
    expect(captured!.arguments, <String, Object?>{'isKeeper': true});
  });

  test('publishPrepared sends the exact candidate and presentation', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });
    final preparedAt = DateTime.utc(2026, 8, 28, 10);
    final activationAt = preparedAt.add(const Duration(hours: 2));

    final result = await KeeperRitualWidgetService().publishPrepared(
      candidate: KeeperRitualWidgetCandidate(
        candidateId: 'east_wisdom_0001:1',
        canonicalText: 'Stay.',
        displayText: 'Kal.',
        wisdomId: 'east_wisdom_0001',
        preparedAt: preparedAt,
        activationAt: activationAt,
      ),
      appearanceMode: EastAppearanceMode.dark,
      localeOverrideTag: 'tr',
    );

    expect(result, isTrue);
    expect(captured!.method, 'publishKeeperPrepared');
    expect(captured!.arguments, <String, Object?>{
      'candidateId': 'east_wisdom_0001:1',
      'canonicalText': 'Stay.',
      'displayText': 'Kal.',
      'wisdomId': 'east_wisdom_0001',
      'preparedAtMillis': preparedAt.millisecondsSinceEpoch,
      'activationAtMillis': activationAt.millisecondsSinceEpoch,
      'appearanceMode': 'dark',
      'localeOverrideTag': 'tr',
    });
  });

  test('publishActive preserves reveal identity and UTC boundaries', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });
    final revealedAt = DateTime.utc(2026, 8, 28, 10);
    final unlockAt = revealedAt.add(const Duration(hours: 24));

    expect(
      await KeeperRitualWidgetService().publishActive(
        reveal: KeeperRitualWidgetReveal(
          candidateId: 'east_wisdom_0001:1',
          canonicalText: 'Stay.',
          displayText: 'Stay.',
          wisdomId: 'east_wisdom_0001',
          revealedAt: revealedAt,
          unlockAt: unlockAt,
          revealId: '10aa0d85-f9c4-4814-ac70-ff3284877c13',
          needsAppCommit: false,
        ),
        appearanceMode: EastAppearanceMode.system,
        localeOverrideTag: null,
      ),
      isTrue,
    );
    expect(captured!.method, 'publishKeeperActive');
    final arguments = captured!.arguments as Map;
    expect(arguments['revealedAtMillis'], revealedAt.millisecondsSinceEpoch);
    expect(arguments['unlockAtMillis'], unlockAt.millisecondsSinceEpoch);
    expect(
      arguments['revealId'],
      '10aa0d85-f9c4-4814-ac70-ff3284877c13',
    );
    expect(arguments['appearanceMode'], 'system');
    expect(arguments.containsKey('localeOverrideTag'), isTrue);
    expect(arguments['localeOverrideTag'], isNull);
    expect(arguments.containsKey('needsAppCommit'), isFalse);
  });

  test('every write contains native failure and reports false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'native_failure');
    });

    expect(
      await KeeperRitualWidgetService().setKeeperEntitlement(true),
      isFalse,
    );
    expect(
      await KeeperRitualWidgetService().publishPrepared(
        candidate: KeeperRitualWidgetCandidate(
          candidateId: 'east_wisdom_0001:1',
          canonicalText: 'Stay.',
          displayText: 'Stay.',
          wisdomId: 'east_wisdom_0001',
          preparedAt: DateTime.utc(2026),
          activationAt: DateTime.utc(2026),
        ),
        appearanceMode: EastAppearanceMode.light,
        localeOverrideTag: null,
      ),
      isFalse,
    );
  });
}
