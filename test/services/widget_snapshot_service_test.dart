// EAST. Phase 11 -- WidgetSnapshotService: exact channel contract, argument
// shape, and full failure containment (never throws).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/services/widget_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(WidgetSnapshotService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void setMethodHandler(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(methodChannel, handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('channelName is the documented value', () {
    expect(
      WidgetSnapshotService.channelName,
      'com.dogukan.dailywisdom/widget_snapshot',
    );
  });

  group('publishRevealed', () {
    test('invokes publishRevealed with text and unlockAtMillis in UTC',
        () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      final unlockAt = DateTime.utc(2026, 8, 16, 12);
      await service.publishRevealed(text: 'Be water.', unlockAt: unlockAt);

      expect(captured, isNotNull);
      expect(captured!.method, 'publishRevealed');
      final args = captured!.arguments as Map;
      expect(args['text'], 'Be water.');
      expect(args['unlockAtMillis'], unlockAt.millisecondsSinceEpoch);
    });

    test(
        'a local (non-UTC) unlockAt is converted to UTC millis before '
        'crossing the channel', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      final localUnlockAt = DateTime(2026, 8, 16, 12);
      await service.publishRevealed(
        text: 'Be water.',
        unlockAt: localUnlockAt,
      );

      final args = captured!.arguments as Map;
      expect(
        args['unlockAtMillis'],
        localUnlockAt.toUtc().millisecondsSinceEpoch,
      );
    });

    test('never throws when no native handler is registered', () async {
      final service = WidgetSnapshotService();
      await expectLater(
        service.publishRevealed(
          text: 'Be water.',
          unlockAt: DateTime.utc(2026, 8, 16),
        ),
        completes,
      );
    });

    test('never throws when the native handler reports an error', () async {
      setMethodHandler((call) async {
        throw PlatformException(code: 'native_failure');
      });

      final service = WidgetSnapshotService();
      await expectLater(
        service.publishRevealed(
          text: 'Be water.',
          unlockAt: DateTime.utc(2026, 8, 16),
        ),
        completes,
      );
    });
  });

  group('publishSilence', () {
    test('invokes publishSilence with no arguments', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      await service.publishSilence();

      expect(captured, isNotNull);
      expect(captured!.method, 'publishSilence');
      expect(captured!.arguments, isNull);
    });

    test('never throws when no native handler is registered', () async {
      final service = WidgetSnapshotService();
      await expectLater(service.publishSilence(), completes);
    });

    test('never throws when the native handler reports an error', () async {
      setMethodHandler((call) async {
        throw PlatformException(code: 'native_failure');
      });

      final service = WidgetSnapshotService();
      await expectLater(service.publishSilence(), completes);
    });
  });
}
