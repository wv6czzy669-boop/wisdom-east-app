import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/private_writing_lock_controller.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/theme/east_design.dart';
import 'package:wisdom_app/services/data_export_service.dart';
import 'package:wisdom_app/services/journal_owner_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'journal_owner_test_helpers.dart';
import 'persistence_test_helpers.dart';

class FakeWritingLockBridge implements PrivateWritingLockBridge {
  bool enabled = true;
  bool available = true;
  bool failStatus = false;
  Completer<bool>? pending;
  var attempts = 0;
  var frameAcks = 0;
  final sensitive = <bool>[];
  @override
  Future<Map<Object?, Object?>> status() async {
    if (failStatus) throw StateError('unavailable');
    return {'enabled': enabled, 'available': available};
  }

  @override
  Future<bool> authenticate(String reason) {
    attempts++;
    return (pending = Completer<bool>()).future;
  }

  @override
  Future<Map<Object?, Object?>> setEnabled(bool value, String reason) async {
    final success = await authenticate(reason);
    if (success) enabled = value;
    return {...await status(), 'authenticated': success};
  }

  @override
  Future<void> setSensitive(bool value) async {
    sensitive.add(value);
  }

  @override
  Future<void> protectedFrameReady() async {
    frameAcks++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in EastTypographyResolver.productionFonts) {
      await (FontLoader(font.family)..addFont(rootBundle.load(font.asset)))
          .load();
    }
  });
  late FakeWritingLockBridge bridge;
  late PrivateWritingLockController lock;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bridge = FakeWritingLockBridge();
    lock = PrivateWritingLockController(bridge: bridge);
  });
  tearDown(() => lock.dispose());

  test('unknown status and failed authentication never reveal private writing',
      () async {
    expect(lock.canRead, isFalse);
    bridge.failStatus = true;
    await lock.load();
    expect(lock.loaded, isFalse);
    expect(lock.canRead, isFalse);
    bridge.failStatus = false;
    final scope = Object();
    await lock.enter(scope);
    final attempt = lock.unlock('Open writing');
    await Future<void>.delayed(Duration.zero);
    bridge.pending!.complete(false);
    expect(await attempt, isFalse);
    expect(lock.canRead, isFalse);
    lock.leave(scope);
  });

  test(
      'one foreground visit shares authentication; leaving all writing locks it again',
      () async {
    final kept = Object(), reflection = Object();
    await lock.enter(kept);
    final attempt = lock.unlock('Open writing');
    await Future<void>.delayed(Duration.zero);
    bridge.pending!.complete(true);
    expect(await attempt, isTrue);
    await lock.enter(reflection);
    expect(await lock.unlock('Open writing'), isTrue);
    expect(bridge.attempts, 1);
    lock.leave(reflection);
    expect(lock.canRead, isTrue);
    lock.leave(kept);
    expect(lock.canRead, isFalse);
  });

  test(
      'background invalidates an in-flight success instead of unlocking on return',
      () async {
    await lock.enter(Object());
    final attempt = lock.unlock('Open writing');
    await Future<void>.delayed(Duration.zero);
    lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
    lock.didChangeAppLifecycleState(AppLifecycleState.paused);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    bridge.pending!.complete(true);
    expect(await attempt, isFalse);
    expect(lock.canRead, isFalse);
  });

  test('system authentication inactivity is not mistaken for leaving the app',
      () async {
    await lock.enter(Object());
    final attempt = lock.unlock('Open writing');
    await Future<void>.delayed(Duration.zero);
    lock.didChangeAppLifecycleState(AppLifecycleState.inactive);
    bridge.pending!.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(lock.canRead, isFalse);
    lock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(await attempt, isTrue);
    expect(lock.canRead, isTrue);
  });

  test(
      'disabling the lock requires authentication and duplicate requests do not prompt twice',
      () async {
    final attempt = lock.changeEnabled(false, 'Change lock');
    await Future<void>.delayed(Duration.zero);
    expect(await lock.changeEnabled(false, 'Change lock'), isFalse);
    bridge.pending!.complete(false);
    expect(await attempt, isFalse);
    expect(lock.enabled, isTrue);
    expect(bridge.attempts, 1);
  });

  Widget app(Widget child,
          {Locale locale = const Locale('en'), double scale = 1}) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: eastTheme(locale: locale).copyWith(platform: TargetPlatform.iOS),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: child,
      );

  testWidgets(
      'all private destinations hide their content and semantics before authentication',
      (tester) async {
    final graph = KeptRepositoryTestGraph();
    final item = (await graph.repository.keepOccurrence(
            revealId: 'aaaaaaaa-0000-4000-8000-000000000001',
            wisdomText: 'Private wisdom.',
            revealedAt: DateTime.utc(2026, 9, 1),
            isKeeper: true))
        .items
        .single;
    for (final screen in <Widget>[
      SavedReflectionsScreen(
          reflections: [item],
          savedReflectionsService: graph.service,
          writingLockController: lock),
      ReflectionScreen(
          item: item,
          isKeeper: true,
          savedReflectionsService: graph.service,
          writingLockController: lock),
      JournalScreen(items: [item], isKeeper: true, writingLockController: lock),
    ]) {
      final previousAttempts = bridge.attempts;
      await tester.pumpWidget(app(screen));
      await tester.pumpAndSettle();
      expect(lock.loaded, isTrue,
          reason: 'The native preference must resolve.');
      expect(bridge.attempts, previousAttempts + 1,
          reason: 'A new private visit requests authentication.');
      expect(
          find.byKey(const ValueKey('private-writing-locked')), findsOneWidget);
      expect(find.text('Private wisdom.'), findsNothing);
      final semantics = tester.ensureSemantics();
      expect(find.semantics.byLabel(RegExp('Private wisdom')), findsNothing);
      semantics.dispose();
      bridge.pending!.complete(false);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'Reflection keeps its draft while locked and resumes after a fresh authentication',
      (tester) async {
    final graph = KeptRepositoryTestGraph();
    final item = (await graph.repository.keepOccurrence(
            revealId: 'aaaaaaaa-0000-4000-8000-000000000001',
            wisdomText: 'Private wisdom.',
            revealedAt: DateTime.utc(2026, 9, 1),
            isKeeper: true))
        .items
        .single;
    await tester.pumpWidget(app(ReflectionScreen(
        item: item,
        isKeeper: true,
        savedReflectionsService: graph.service,
        writingLockController: lock)));
    await tester.pumpAndSettle();
    bridge.pending!.complete(true);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('reflection-writing-area'));
    await tester.enterText(field, 'These words stay mine.');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(find.text('These words stay mine.'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(bridge.frameAcks, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('private-writing-unlock')));
    await tester.pump();
    bridge.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,
        'These words stay mine.');
    expect((await graph.service.load()).single.reflection,
        'These words stay mine.');
  });

  testWidgets(
      'Settings puts everyday preferences first and moves destructive actions and links into details',
      (tester) async {
    bridge.enabled = false;
    await tester.pumpWidget(app(SettingsScreen(writingLockController: lock)));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Language')).dy,
        lessThan(tester.getTopLeft(find.text('Keeper')).dy));
    expect(find.byKey(const ValueKey('settings-remove-from-icloud-row')),
        findsNothing);
    expect(find.byKey(const ValueKey('settings-east-productions-row')),
        findsNothing);
    final about = find.byKey(const ValueKey('settings-about-row'));
    await tester.ensureVisible(about);
    await tester.tap(about);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-east-productions-row')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();
    final sync = find.byKey(const ValueKey('settings-icloud-sync-row'));
    await tester.ensureVisible(sync);
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-remove-from-icloud-row')),
        findsOneWidget);
  });

  testWidgets(
      'Settings exports only after authentication and waits for the foreground',
      (tester) async {
    final graph = KeptRepositoryTestGraph();
    var shares = 0;
    final export = DataExportService(
      savedReflectionsServiceProvider: () => graph.service,
      journalOwnerService:
          JournalOwnerService(ownerStore: InMemoryJournalOwnerStore()),
      shareLauncher: (_) async {
        shares++;
        return const ShareResult('', ShareResultStatus.success);
      },
    );
    await tester.pumpWidget(app(SettingsScreen(
        writingLockController: lock, dataExportService: export)));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-export-data-row'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(shares, 0);
    bridge.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(shares, 0);
    await tester.tap(row);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    bridge.pending!.complete(true);
    await tester.pump();
    expect(shares, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(shares, 1);
    expect(bridge.attempts, 2);
    expect(bridge.sensitive.last, isFalse);
  });

  testWidgets('the lock switch confirms identity before changing its value',
      (tester) async {
    bridge.enabled = false;
    await tester.pumpWidget(app(SettingsScreen(
        section: SettingsSection.privacy, writingLockController: lock)));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-writing-lock-toggle'));
    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isFalse);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(lock.enabled, isFalse);
    bridge.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue);
    await tester.tap(row);
    await tester.pumpAndSettle();
    bridge.pending!.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue);
  });

  testWidgets(
      'an unread lock preference shows Retry and never pretends to be off',
      (tester) async {
    bridge.failStatus = true;
    await tester.pumpWidget(app(SettingsScreen(
        section: SettingsSection.privacy, writingLockController: lock)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNothing);
    bridge.failStatus = false;
    await tester
        .tap(find.byKey(const ValueKey('settings-writing-lock-toggle')));
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue);
    expect(bridge.attempts, 0);
  });

  testWidgets(
      'every Settings section stays usable in every locale at 200 percent on a small iPhone',
      (tester) async {
    bridge.enabled = false;
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in AppLocalizations.supportedLocales) {
      for (final section in SettingsSection.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(app(
            SettingsScreen(section: section, writingLockController: lock),
            locale: locale,
            scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale / $section');
      }
    }
  });
}
