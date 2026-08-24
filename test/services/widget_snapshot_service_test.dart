// EAST. Phase 11, extended in 1.2 Slice 3 -- WidgetSnapshotService: exact
// channel contract, argument shape (including the presentation fields),
// UTC conversion, and full failure containment (never throws).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/appearance_preference_controller.dart';
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
    test(
        'invokes publishRevealed with exactly text, unlockAtMillis (UTC), '
        'appearanceMode, and localeOverrideTag', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      final unlockAt = DateTime.utc(2026, 8, 16, 12);
      await service.publishRevealed(
        text: 'Be water.',
        unlockAt: unlockAt,
        appearanceMode: EastAppearanceMode.dark,
        localeOverrideTag: 'tr',
      );

      expect(captured, isNotNull);
      expect(captured!.method, 'publishRevealed');
      final args = captured!.arguments as Map;
      expect(
        args.keys.toSet(),
        {'text', 'unlockAtMillis', 'appearanceMode', 'localeOverrideTag'},
      );
      expect(args['text'], 'Be water.');
      expect(args['unlockAtMillis'], unlockAt.millisecondsSinceEpoch);
      expect(args['appearanceMode'], 'dark');
      expect(args['localeOverrideTag'], 'tr');
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
        appearanceMode: EastAppearanceMode.system,
        localeOverrideTag: null,
      );

      final args = captured!.arguments as Map;
      expect(
        args['unlockAtMillis'],
        localUnlockAt.toUtc().millisecondsSinceEpoch,
      );
    });

    test('light/dark/system each encode to their exact documented wire value',
        () async {
      final captures = <MethodCall>[];
      setMethodHandler((call) async {
        captures.add(call);
        return null;
      });

      final service = WidgetSnapshotService();
      for (final mode in EastAppearanceMode.values) {
        await service.publishRevealed(
          text: 'Be water.',
          unlockAt: DateTime.utc(2026, 8, 16),
          appearanceMode: mode,
          localeOverrideTag: null,
        );
      }

      expect(
        captures.map((call) => (call.arguments as Map)['appearanceMode']),
        ['system', 'light', 'dark'],
      );
    });

    test('an explicit locale override tag crosses verbatim', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      await service.publishRevealed(
        text: 'Be water.',
        unlockAt: DateTime.utc(2026, 8, 16),
        appearanceMode: EastAppearanceMode.system,
        localeOverrideTag: 'zh-Hant',
      );

      expect((captured!.arguments as Map)['localeOverrideTag'], 'zh-Hant');
    });

    test(
        'System Default sends localeOverrideTag as an explicitly present '
        'null key, never an absent key', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      await service.publishRevealed(
        text: 'Be water.',
        unlockAt: DateTime.utc(2026, 8, 16),
        appearanceMode: EastAppearanceMode.system,
        localeOverrideTag: null,
      );

      final args = captured!.arguments as Map;
      expect(args.containsKey('localeOverrideTag'), isTrue);
      expect(args['localeOverrideTag'], isNull);
    });

    test('never throws when no native handler is registered', () async {
      final service = WidgetSnapshotService();
      await expectLater(
        service.publishRevealed(
          text: 'Be water.',
          unlockAt: DateTime.utc(2026, 8, 16),
          appearanceMode: EastAppearanceMode.system,
          localeOverrideTag: null,
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
          appearanceMode: EastAppearanceMode.system,
          localeOverrideTag: null,
        ),
        completes,
      );
    });
  });

  group('publishSilence', () {
    test(
        'invokes publishSilence with exactly appearanceMode and '
        'localeOverrideTag', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      await service.publishSilence(
        appearanceMode: EastAppearanceMode.light,
        localeOverrideTag: 'pt-BR',
      );

      expect(captured, isNotNull);
      expect(captured!.method, 'publishSilence');
      final args = captured!.arguments as Map;
      expect(args.keys.toSet(), {'appearanceMode', 'localeOverrideTag'});
      expect(args['appearanceMode'], 'light');
      expect(args['localeOverrideTag'], 'pt-BR');
    });

    test(
        'System Default sends localeOverrideTag as an explicitly present '
        'null key', () async {
      MethodCall? captured;
      setMethodHandler((call) async {
        captured = call;
        return null;
      });

      final service = WidgetSnapshotService();
      await service.publishSilence(
        appearanceMode: EastAppearanceMode.system,
        localeOverrideTag: null,
      );

      final args = captured!.arguments as Map;
      expect(args.containsKey('localeOverrideTag'), isTrue);
      expect(args['localeOverrideTag'], isNull);
    });

    test('never throws when no native handler is registered', () async {
      final service = WidgetSnapshotService();
      await expectLater(
        service.publishSilence(
          appearanceMode: EastAppearanceMode.system,
          localeOverrideTag: null,
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
        service.publishSilence(
          appearanceMode: EastAppearanceMode.system,
          localeOverrideTag: null,
        ),
        completes,
      );
    });
  });
}
