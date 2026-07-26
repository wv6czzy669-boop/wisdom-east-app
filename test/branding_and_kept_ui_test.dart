import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/data/objects_catalog.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/services/notification_settings_launcher.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';

void main() {
  setUp(() {
    // The Daily Reminder row reads/writes a Daily-Reminder preference
    // through the real `WisdomNotificationService` singleton whenever a
    // test does not inject its own `notificationService`. Seeding an empty
    // mock store keeps every test in this file isolated and deterministic.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('application and settings use EAST. branding', (tester) async {
    await tester.pumpWidget(const WisdomApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Daily Wisdom: EAST.');

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 550));

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.text('EAST.'), findsOneWidget);
    expect(find.text('Where silence speaks.'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Where silence speaks.')).style?.color,
      eastMutedTextColor,
    );
    expect(
      find.text('Support the circle, keep what stays.'),
      findsOneWidget,
    );
    expect(
      find.text('Restore what belongs with you.'),
      findsOneWidget,
    );
    expect(find.text('What stays private.'), findsOneWidget);
    expect(find.text('For thoughts and questions.'), findsOneWidget);
    expect(find.text('Reach Out'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(
      tester
          .widget<Align>(
            find.byKey(const ValueKey('settings-content')),
          )
          .alignment,
      Alignment.topCenter,
    );
    expect(tester.getTopLeft(find.text('EAST.')).dy, lessThan(100));
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('settings-scroll')),
          )
          .physics,
      isA<ClampingScrollPhysics>(),
    );
    final settingsScroll = find.byKey(
      const ValueKey('settings-scroll'),
    );
    expect(
      find.descendant(of: settingsScroll, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(
      find.descendant(of: settingsScroll, matching: find.byType(CustomPaint)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('keeper-circle-symbol')), findsNothing);
    expect(find.text('○'), findsNothing);
    expect(tester.getTopLeft(find.text('Keeper')).dx, 24);
  });

  testWidgets(
      'every Settings divider shares the muted color at ~30% opacity, and '
      'the row order is Keeper, Restore Purchases, Daily Reminder, '
      'EAST. Productions, Privacy Policy, Reach Out', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(7));

    final expectedDividerColor = eastMutedTextColor.withValues(alpha: 0.30);
    for (final divider in dividers) {
      expect(divider.color, expectedDividerColor);
      expect(divider.thickness, 0.5);
    }

    final rowOrder = [
      'Keeper',
      'Restore Purchases',
      'Daily Reminder',
      'EAST. Productions',
      'Privacy Policy',
      'Reach Out',
    ];
    for (var i = 0; i < rowOrder.length - 1; i++) {
      expect(
        tester.getTopLeft(find.text(rowOrder[i])).dy,
        lessThan(tester.getTopLeft(find.text(rowOrder[i + 1])).dy),
      );
    }

    // "Where silence speaks." keeps its already-approved color untouched by
    // the new shared divider color.
    expect(
      tester.widget<Text>(find.text('Where silence speaks.')).style?.color,
      eastMutedTextColor,
    );
  });

  testWidgets(
      'exactly one EAST. Productions row exists, with the exact title and '
      'subtitle, no icon, and no chevron', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.text('EAST. Productions'), findsOneWidget);
    expect(find.text('The world beyond the ritual.'), findsOneWidget);

    final settingsScroll = find.byKey(const ValueKey('settings-scroll'));
    expect(
      find.descendant(of: settingsScroll, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios), findsNothing);
  });

  testWidgets(
      'EAST. Productions launch success targets the root domain '
      'externally with no confirmation or feedback', (tester) async {
    final calls = <_LaunchCall>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async {
            calls.add(_LaunchCall(uri: uri, mode: mode));
            return true;
          },
        ),
      ),
    );

    final eastProductionsRow =
        find.byKey(const ValueKey('settings-east-productions-row'));
    await tester.ensureVisible(eastProductionsRow);
    await tester.pump();
    await tester.tap(eastProductionsRow);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.uri.toString(), 'https://east.productions');
    expect(calls.single.mode, LaunchMode.externalApplication);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'EAST. Productions launch failure or throw shows restrained feedback '
      'without crashing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async => false,
        ),
      ),
    );

    final eastProductionsRow =
        find.byKey(const ValueKey('settings-east-productions-row'));
    await tester.ensureVisible(eastProductionsRow);
    await tester.pump();
    await tester.tap(eastProductionsRow);
    await tester.pump();

    expect(
      find.text('EAST. Productions could not be opened.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async {
            throw StateError('blocked');
          },
        ),
      ),
    );

    await tester.ensureVisible(eastProductionsRow);
    await tester.pump();
    await tester.tap(eastProductionsRow);
    await tester.pump();

    expect(
      find.text('EAST. Productions could not be opened.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'EAST. Productions row exposes one combined actionable '
      'semantic node distinct from Objects', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            urlLauncher: (uri, {required mode}) async => true,
          ),
        ),
      );

      _expectSemanticNode(
        label: 'EAST. Productions. The world beyond the ritual.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'the Objects-screen link still targets /objects, distinct from the '
      'Settings row targeting the root domain', (tester) async {
    expect(
      ObjectsCatalog.discoverObjectsUrl,
      'https://east.productions/objects',
    );
  });

  testWidgets('Kept displays the full stored date with year', (tester) async {
    const storedDate = 'June 21, 2026';
    final reflection = FavoriteItem(
      id: 'kept-year-test',
      text: 'A quiet reflection.',
      date: storedDate,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: [reflection],
        ),
      ),
    );

    expect(find.text('JUNE 21, 2026'), findsOneWidget);
    final displayedDate = tester.widget<Text>(find.text('JUNE 21, 2026'));
    expect(displayedDate.style?.color, eastMutedTextColor);
    expect(reflection.date, storedDate);
  });

  testWidgets('Kept screen uses the quiet empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SavedReflectionsScreen(reflections: []),
      ),
    );

    expect(find.text('Kept'), findsOneWidget);
    expect(find.text('Nothing has stayed yet.'), findsOneWidget);
  });

  testWidgets('Settings scroll protects iPhone SE at 3x text scale',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text('Reach Out'), findsOneWidget);

    await tester.ensureVisible(find.text('Reach Out'));
    await tester.pump();

    expect(
      tester.getCenter(find.text('Reach Out')).dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Keeper row tap pushes exactly one Keeper route', (tester) async {
    // A single completed gesture on Keeper immediately pushes a new route
    // that covers the Settings list — there is no physically deliverable
    // second tap on the same row once that has happened (a real second
    // finger-down could only ever land on whatever is now on top, i.e.
    // Keeper itself). So this proves the one-push guarantee with a real
    // tap plus a NavigatorObserver, rather than forcing an impossible
    // duplicate-tap model onto an instantaneous route push.
    final observer = _PushCountingNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        home: const SettingsScreen(),
        navigatorObservers: [observer],
      ),
    );

    final keeperRow = find.byKey(const ValueKey('settings-keeper-row'));
    await tester.tap(keeperRow);
    await tester.pumpAndSettle();

    expect(observer.pushCount, 1);
    expect(find.text('Enter the Circle'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the Circle'), findsNothing);
    expect(find.text('Support the circle, keep what stays.'), findsOneWidget);
  });

  testWidgets('Privacy Policy launch success shows no failure feedback',
      (tester) async {
    final calls = <_LaunchCall>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async {
            calls.add(_LaunchCall(uri: uri, mode: mode));
            return true;
          },
        ),
      ),
    );

    final privacyPolicyRow =
        find.byKey(const ValueKey('settings-privacy-policy-row'));
    await tester.ensureVisible(privacyPolicyRow);
    await tester.pump();
    await tester.tap(privacyPolicyRow);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.uri.scheme, 'https');
    expect(calls.single.mode, LaunchMode.externalApplication);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Privacy Policy launch false shows restrained feedback',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async => false,
        ),
      ),
    );

    final privacyPolicyRow =
        find.byKey(const ValueKey('settings-privacy-policy-row'));
    await tester.ensureVisible(privacyPolicyRow);
    await tester.pump();
    await tester.tap(privacyPolicyRow);
    await tester.pump();

    expect(find.text('Privacy Policy could not be opened.'), findsOneWidget);
  });

  testWidgets('Privacy Policy launch throw shows restrained feedback',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async {
            throw StateError('blocked');
          },
        ),
      ),
    );

    final privacyPolicyRow =
        find.byKey(const ValueKey('settings-privacy-policy-row'));
    await tester.ensureVisible(privacyPolicyRow);
    await tester.pump();
    await tester.tap(privacyPolicyRow);
    await tester.pump();

    expect(find.text('Privacy Policy could not be opened.'), findsOneWidget);
  });

  testWidgets('Reach Out launch success uses mailto without feedback',
      (tester) async {
    final calls = <_LaunchCall>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async {
            calls.add(_LaunchCall(uri: uri, mode: mode));
            return true;
          },
        ),
      ),
    );

    final reachOutRow = find.byKey(const ValueKey('settings-reach-out-row'));
    await tester.ensureVisible(reachOutRow);
    await tester.pump();
    await tester.tap(reachOutRow);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.uri.scheme, 'mailto');
    expect(calls.single.uri.path, 'hello@east.productions');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Reach Out launch false or throw shows feedback', (tester) async {
    final reachOutRow = find.byKey(const ValueKey('settings-reach-out-row'));

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async => false,
        ),
      ),
    );

    await tester.ensureVisible(reachOutRow);
    await tester.pump();
    await tester.tap(reachOutRow);
    await tester.pump();

    expect(find.text('Reach Out could not be opened.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async {
            throw StateError('blocked');
          },
        ),
      ),
    );

    await tester.ensureVisible(reachOutRow);
    await tester.pump();
    await tester.tap(reachOutRow);
    await tester.pump();

    expect(find.text('Reach Out could not be opened.'), findsOneWidget);
  });

  testWidgets('rapid external taps produce one launch and one failure feedback',
      (tester) async {
    final launchCompleter = Completer<bool>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) {
            calls += 1;
            return launchCompleter.future;
          },
        ),
      ),
    );

    final privacyPolicyRow =
        find.byKey(const ValueKey('settings-privacy-policy-row'));
    await tester.ensureVisible(privacyPolicyRow);
    await tester.pump();

    await tester.tap(privacyPolicyRow);
    // Pump only enough to dispatch the tap and let the row's own async
    // work reach the still-open `launchCompleter` — the row is now
    // genuinely in flight (its onTap becomes null while busy).
    await tester.pump();
    expect(calls, 1);

    // A second real tap while the first launch is still pending. Since
    // the row is disabled in this state, this dispatches to a widget with
    // no active tap handler, exactly as a real user's second tap would.
    await tester.tap(privacyPolicyRow);
    await tester.pump();

    expect(calls, 1);

    launchCompleter.complete(false);
    await tester.pump();
    await tester.pump();

    expect(find.text('Privacy Policy could not be opened.'), findsOneWidget);
  });

  testWidgets('external failure feedback is skipped after disposal',
      (tester) async {
    final launchCompleter = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) => launchCompleter.future,
        ),
      ),
    );

    final privacyPolicyRow =
        find.byKey(const ValueKey('settings-privacy-policy-row'));
    await tester.ensureVisible(privacyPolicyRow);
    await tester.pump();
    await tester.tap(privacyPolicyRow);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    launchCompleter.complete(false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Privacy Policy could not be opened.'), findsNothing);
  });

  testWidgets('Settings rows expose one combined actionable semantic node',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            urlLauncher: (uri, {required mode}) async => true,
          ),
        ),
      );

      _expectSemanticNode(
        label: 'Restore Purchases. Restore what belongs with you.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );
      _expectSemanticNode(
        label: 'Privacy Policy. What stays private.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );
      _expectSemanticNode(
        label: 'Reach Out. For thoughts and questions.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Restore in progress remains a disabled semantic button',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            purchaseService: _SettingsPurchaseService(loading: true),
          ),
        ),
      );

      _expectSemanticNode(
        label: 'Restore Purchases. Restore in progress.',
        isButton: true,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Privacy opening remains a disabled button without relaunch',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final launchCompleter = Completer<bool>();
    var calls = 0;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            urlLauncher: (uri, {required mode}) {
              calls += 1;
              return launchCompleter.future;
            },
          ),
        ),
      );

      final privacyPolicyRow =
          find.byKey(const ValueKey('settings-privacy-policy-row'));
      await tester.ensureVisible(privacyPolicyRow);
      await tester.pump();
      await tester.tap(privacyPolicyRow);
      await tester.pump();

      _expectSemanticNode(
        label: 'Privacy Policy. Opening.',
        isButton: true,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );

      await tester.tap(privacyPolicyRow);
      await tester.pump();

      expect(calls, 1);

      launchCompleter.complete(true);
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Reach Out opening remains a disabled button without relaunch',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final launchCompleter = Completer<bool>();
    var calls = 0;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            urlLauncher: (uri, {required mode}) {
              calls += 1;
              return launchCompleter.future;
            },
          ),
        ),
      );

      final reachOutRow = find.byKey(const ValueKey('settings-reach-out-row'));
      await tester.ensureVisible(reachOutRow);
      await tester.pump();
      await tester.tap(reachOutRow);
      await tester.pump();

      _expectSemanticNode(
        label: 'Reach Out. Opening.',
        isButton: true,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );

      await tester.tap(reachOutRow);
      await tester.pump();

      expect(calls, 1);

      launchCompleter.complete(true);
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });

  group('Daily Reminder row', () {
    Finder rowFinder(WidgetTester tester) {
      final finder = find.byKey(const ValueKey('settings-daily-reminder-row'));
      return finder;
    }

    testWidgets(
        'shows the exact title, subtitle, and no switch/checkbox/chevron/'
        'icon; trailing reads ON in the warm off-white color when '
        'authorized', (tester) async {
      final platform = _FakeReminderPlatform(enabled: true);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            notificationService: WisdomNotificationService(platform: platform),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Daily Reminder'), findsOneWidget);
      expect(
        find.text('Return when the silence opens again.'),
        findsOneWidget,
      );
      expect(find.text('ON'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('ON')).style?.color,
        const Color(0xFFF4F0E8),
      );

      final row = rowFinder(tester);
      expect(
        find.descendant(of: row, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(Checkbox)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets(
        'trailing reads OFF in the shared muted color when the system is '
        'not authorized', (tester) async {
      final platform = _FakeReminderPlatform(enabled: false);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            notificationService: WisdomNotificationService(platform: platform),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('OFF'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('OFF')).style?.color,
        eastMutedTextColor,
      );
    });

    testWidgets(
        'tapping while ON turns it OFF, cancels the pending reminder, and '
        'never requests native permission', (tester) async {
      final platform = _FakeReminderPlatform(enabled: true);
      final service = WisdomNotificationService(platform: platform);
      await service.scheduleFromAuthoritativeUnlock(
        DateTime.now().add(const Duration(hours: 24)),
      );
      final scheduledBefore = platform.scheduled.length;

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(notificationService: service)),
      );
      await tester.pump();
      expect(find.text('ON'), findsOneWidget);

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();

      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('ON'), findsNothing);
      expect(platform.permissionRequests, 0);
      expect(platform.cancelled, isNotEmpty);
      expect(platform.scheduled.length, scheduledBefore);
      expect(
          await service.reminderPreference(), DailyReminderPreference.disabled);
    });

    testWidgets(
        'tapping while OFF and notDetermined requests native permission '
        'directly, with no app-owned dialog, and shows ON when granted',
        (tester) async {
      final platform = _FakeReminderPlatform(enabled: false)
        ..permissionResult = true;
      final service = WisdomNotificationService(platform: platform);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(notificationService: service)),
      );
      await tester.pump();
      expect(find.text('OFF'), findsOneWidget);

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();

      expect(platform.permissionRequests, 1);
      expect(find.text('ON'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Not now'), findsNothing);
    });

    testWidgets(
        'tapping while OFF and denied calls the injected native '
        'notification-settings launcher exactly once, never url_launcher, '
        'and shows no custom explanatory dialog', (tester) async {
      final platform = _FakeReminderPlatform(enabled: false);
      final settingsLauncher = _FakeSettingsLauncher(result: true);
      final service = WisdomNotificationService(
        platform: platform,
        settingsLauncher: settingsLauncher,
      );
      await service.dismissPermissionOffer();
      final urlLauncherCalls = <_LaunchCall>[];

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            notificationService: service,
            urlLauncher: (uri, {required mode}) async {
              urlLauncherCalls.add(_LaunchCall(uri: uri, mode: mode));
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();

      expect(platform.permissionRequests, 0);
      expect(settingsLauncher.calls, 1);
      expect(urlLauncherCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Not now'), findsNothing);
    });

    testWidgets('a successful native settings launch shows no failure feedback',
        (tester) async {
      final platform = _FakeReminderPlatform(enabled: false);
      final settingsLauncher = _FakeSettingsLauncher(result: true);
      final service = WisdomNotificationService(
        platform: platform,
        settingsLauncher: settingsLauncher,
      );
      await service.dismissPermissionOffer();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(notificationService: service)),
      );
      await tester.pump();

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a false result or a thrown platform exception from the native '
        'launcher does not crash the app', (tester) async {
      final platform = _FakeReminderPlatform(enabled: false);
      final falseLauncher = _FakeSettingsLauncher(result: false);
      final falseService = WisdomNotificationService(
        platform: platform,
        settingsLauncher: falseLauncher,
      );
      await falseService.dismissPermissionOffer();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(notificationService: falseService)),
      );
      await tester.pump();

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();

      expect(falseLauncher.calls, 1);
      expect(tester.takeException(), isNull);

      final throwingLauncher = _FakeSettingsLauncher(
        result: false,
        shouldThrow: true,
      );
      final throwingService = WisdomNotificationService(
        platform: _FakeReminderPlatform(enabled: false),
        settingsLauncher: throwingLauncher,
      );
      await throwingService.dismissPermissionOffer();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(notificationService: throwingService),
        ),
      );
      await tester.pump();

      final throwingRow = rowFinder(tester);
      await tester.ensureVisible(throwingRow);
      await tester.pump();
      await tester.tap(throwingRow);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'repeated rapid taps while denied launch the native settings '
        'destination only once, proven while the first launch is still '
        'genuinely in flight', (tester) async {
      final platform = _FakeReminderPlatform(enabled: false);
      final gate = Completer<bool>();
      final settingsLauncher = _FakeSettingsLauncher(result: true, gate: gate);
      final service = WisdomNotificationService(
        platform: platform,
        settingsLauncher: settingsLauncher,
      );
      await service.dismissPermissionOffer();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(notificationService: service)),
      );
      await tester.pump();

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();

      // Real gesture: hit-test and dispatch an actual tap on the row.
      await tester.tap(row);
      // Pump only enough to dispatch the tap and let the row's own async
      // work reach the still-open `gate` — the launcher's future has not
      // resolved yet, so the row is now genuinely in flight (its onTap
      // becomes null while busy, exactly like a real disabled control).
      await tester.pump();
      expect(settingsLauncher.calls, 1);

      // A second real tap while the first launch is still pending. Since
      // the row is disabled in this state, this dispatches to a widget
      // with no active tap handler — the same thing a real user's second
      // tap would hit — rather than an artificially blocked callback.
      await tester.tap(row);
      await tester.pump();

      // The launcher's future has not resolved yet, so this proves the
      // second, re-entrant tap could not reach the launcher a second time.
      expect(settingsLauncher.calls, 1);

      gate.complete(true);
      await tester.pump();
      await tester.pump();

      expect(settingsLauncher.calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'two separate taps after the first Daily Reminder toggle has fully '
        'completed are not duplicates: each one is honoured in turn',
        (tester) async {
      final platform = _FakeReminderPlatform(enabled: true);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            notificationService: WisdomNotificationService(platform: platform),
          ),
        ),
      );
      await tester.pump();

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();

      // First toggle: ON -> OFF. Awaited fully before the next tap, so
      // this is a completed action, not a duplicate.
      await tester.tap(row);
      await tester.pump();
      expect(find.text('OFF'), findsOneWidget);

      // Second toggle, after the first has entirely finished: OFF -> ON.
      // This must be honoured, not blocked, since nothing is in flight.
      await tester.tap(row);
      await tester.pump();
      expect(find.text('ON'), findsOneWidget);
    });

    testWidgets(
        'rapid re-entrant taps while the ON-to-OFF cancellation is still in '
        'flight are serialized into exactly one change', (tester) async {
      final cancelGate = Completer<void>();
      final platform = _FakeReminderPlatform(
        enabled: true,
        cancelGate: cancelGate,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            notificationService: WisdomNotificationService(platform: platform),
          ),
        ),
      );
      await tester.pump();

      final row = rowFinder(tester);
      await tester.ensureVisible(row);
      await tester.pump();
      expect(find.text('ON'), findsOneWidget);

      // Real gesture: hit-test and dispatch an actual tap on the row.
      await tester.tap(row);
      // Pump only enough to dispatch the tap and let the row's own async
      // work reach the still-open `cancelGate` — the cancellation has not
      // resolved yet, so the row is now genuinely in flight (its onTap
      // becomes null while busy).
      await tester.pump();
      expect(platform.cancelled, hasLength(1));

      // A second real tap while the cancellation is still pending. Since
      // the row is disabled in this state, this dispatches to a widget
      // with no active tap handler, exactly as a real user's second tap
      // would.
      await tester.tap(row);
      await tester.pump();

      // The cancellation triggered by the first tap has not resolved yet,
      // so only one cancel call should have been made so far, proving the
      // second, re-entrant tap could not reach the platform a second time.
      expect(platform.cancelled, hasLength(1));

      cancelGate.complete();
      await tester.pump();
      await tester.pump();

      expect(platform.cancelled, hasLength(1));
      expect(find.text('OFF'), findsOneWidget);
      expect(find.text('ON'), findsNothing);
    });

    testWidgets(
        'refreshes the real authorization status on resume without ever '
        'auto-requesting permission', (tester) async {
      final platform = _FakeReminderPlatform(enabled: false);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            notificationService: WisdomNotificationService(platform: platform),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('OFF'), findsOneWidget);

      // Simulate the user granting access from the iOS Settings app, then
      // returning to EAST. in the foreground.
      platform.enabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('ON'), findsOneWidget);
      expect(platform.permissionRequests, 0);
    });

    testWidgets(
        'exposes one combined actionable semantic node with the '
        'current status spoken', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final platform = _FakeReminderPlatform(enabled: true);
        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              notificationService:
                  WisdomNotificationService(platform: platform),
            ),
          ),
        );
        await tester.pump();

        _expectSemanticNode(
          label: 'Daily Reminder. Return when the silence opens again. '
              'Currently on.',
          isButton: true,
          isEnabled: Tristate.isTrue,
          hasTap: true,
        );
      } finally {
        semantics.dispose();
      }
    });
  });
}

class _FakeSettingsLauncher implements NotificationSettingsLauncher {
  _FakeSettingsLauncher({
    required this.result,
    this.shouldThrow = false,
    this.gate,
  });

  final bool result;
  final bool shouldThrow;
  // When set, the launch waits on this Completer before resolving, so a
  // test can hold it genuinely in flight while a second, re-entrant tap is
  // attempted.
  final Completer<bool>? gate;
  int calls = 0;

  @override
  Future<bool> openNotificationSettings() async {
    calls += 1;
    if (shouldThrow) {
      throw PlatformException(code: 'unavailable');
    }
    if (gate != null) {
      return gate!.future;
    }
    return result;
  }
}

class _FakeReminderPlatform implements WisdomNotificationPlatform {
  _FakeReminderPlatform({this.enabled = true, this.cancelGate});

  bool enabled;
  bool permissionResult = false;
  int permissionRequests = 0;
  // When set, `cancel()` waits on this Completer before resolving, so a
  // test can hold the ON-to-OFF disable/cancel path genuinely in flight
  // while a second, re-entrant tap is attempted.
  final Completer<void>? cancelGate;
  final List<String> cancelled = [];
  final List<int> scheduled = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> notificationsEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    if (permissionResult) enabled = true;
    return permissionResult;
  }

  @override
  Future<void> cancel(int id) async {
    // Record the call before waiting on the gate (if any), so a test can
    // prove the call was made — i.e. that it is genuinely in flight —
    // before the gate resolves.
    cancelled.add('cancel:$id');
    if (cancelGate != null) await cancelGate!.future;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  }) async {
    scheduled.add(id);
  }
}

void _expectSemanticNode({
  required String label,
  required bool isButton,
  required Tristate isEnabled,
  required bool hasTap,
}) {
  final matches = find.semantics.byLabel(label).evaluate();
  expect(matches, hasLength(1));
  final data = matches.single.getSemanticsData();
  expect(data.flagsCollection.isButton, isButton);
  expect(data.flagsCollection.isEnabled, isEnabled);
  expect(data.hasAction(SemanticsAction.tap), hasTap);
}

class _PushCountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The Navigator reports the initial route (previousRoute == null) as
    // a "push" too; only count actual navigations away from it.
    if (previousRoute != null) {
      pushCount += 1;
    }
  }
}

class _LaunchCall {
  const _LaunchCall({
    required this.uri,
    required this.mode,
  });

  final Uri uri;
  final LaunchMode mode;
}

class _SettingsPurchaseService extends PurchaseService {
  _SettingsPurchaseService({
    this.loading = false,
  });

  final bool loading;

  @override
  bool get isLoading => loading;

  @override
  bool get restoreNeedsRecovery => false;

  @override
  Future<bool> restorePurchases() async => false;
}
