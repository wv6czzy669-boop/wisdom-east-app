import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/services/purchase_service.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';

import 'persistence_test_helpers.dart';

void main() {
  setUp(() {
    // Keeps every test in this file isolated and deterministic.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('application and settings use EAST. branding', (tester) async {
    // Correction: `WisdomApp` mounts a real `HomeScreen`, whose `initState`
    // falls through to `app_services.savedReflectionsService` (a `late
    // final` production global only ever populated by production's own
    // `initializeKeptStorage()`, which this isolated widget test never
    // runs) whenever no `savedReflectionsService` is supplied. A fresh,
    // isolated `KeptRepositoryTestGraph` (in-memory store only — no
    // Application Support directory, no native file-protection channel, no
    // production global touched, no bootstrap call) is threaded through
    // `WisdomApp`'s own test-only injection seam instead.
    final keptGraph = KeptRepositoryTestGraph();
    await tester.pumpWidget(
      WisdomApp(savedReflectionsService: keptGraph.service),
    );

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
      eastMutedTextColor(tester.element(find.text('Where silence speaks.'))),
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
    expect(find.text('Daily Reminder'), findsNothing);
    expect(
      find.text('Return when the silence opens again.'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-daily-reminder-row')),
      findsNothing,
    );
    expect(find.text('ON'), findsNothing);
    expect(find.text('OFF'), findsNothing);
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
      'Approved EAST Settings direction: exactly two hairlines mark three '
      'groups, and the row order is exactly Keeper, Restore Purchases, '
      'iCloud Sync, Remove from iCloud, EAST. Productions, Privacy Policy, '
      'Reach Out — with no Daily Reminder row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    // Approved direction: "Settings — complete, one screen" replaces the
    // old seven-row/eight-divider menu with three groups (what you can
    // own, what holds your data, the world outside) separated by exactly
    // two hairlines -- air groups siblings within a group, never a rule
    // between them.
    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(2));

    final expectedDividerColor = eastMutedTextColor(
      tester.element(find.byType(SettingsScreen)),
    ).withValues(alpha: 0.30);
    for (final divider in dividers) {
      expect(divider.color, expectedDividerColor);
      expect(divider.thickness, 0.5);
    }

    final rowOrder = [
      'Keeper',
      'Restore Purchases',
      'iCloud Sync',
      'Remove from iCloud',
      'EAST. Productions',
      'Privacy Policy',
      'Reach Out',
    ];
    expect(rowOrder, isNot(contains('Daily Reminder')));
    for (var i = 0; i < rowOrder.length - 1; i++) {
      expect(
        tester.getTopLeft(find.text(rowOrder[i])).dy,
        lessThan(tester.getTopLeft(find.text(rowOrder[i + 1])).dy),
      );
    }

    expect(find.text('Daily Reminder'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-daily-reminder-row')),
      findsNothing,
    );

    // "Where silence speaks." keeps its already-approved color untouched by
    // the new shared divider color.
    expect(
      tester.widget<Text>(find.text('Where silence speaks.')).style?.color,
      eastMutedTextColor(tester.element(find.text('Where silence speaks.'))),
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
      find.text('This could not be completed. Please try again.'),
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
      find.text('This could not be completed. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'EAST. Productions row exposes one combined actionable semantic node',
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
        label: 'EAST. Productions. The world beyond the ritual.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Kept displays the full stored date with year', (tester) async {
    // Correction: seeds a real protected Kept occurrence (canonical UUID v4
    // identity, never a text/date-derived identity) through an isolated
    // `KeptRepositoryTestGraph` — in-memory only, no SharedPreferences, no
    // Application Support directory, no native file protection — then
    // loads it exactly the way `HomeScreen` itself does before pushing
    // this screen (`reflections: List<FavoriteItem>.from(favorites)` +
    // `savedReflectionsService: savedReflectionsService`), so the screen
    // never falls through to the uninitialized production
    // `app_services.savedReflectionsService`.
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        KeptRecord(
          id: 'kept-year-test',
          revealId: 'a5f3c111-1111-4111-8111-111111111111',
          wisdomText: 'A quiet reflection.',
          revealedAt: DateTime(2026, 6, 21, 12),
          keptAt: DateTime(2026, 6, 21, 12),
          updatedAt: DateTime(2026, 6, 21, 12),
          mutationId: 'a5f3c111-2222-4222-8222-222222222222',
        ),
      ]);
    final reflections = await keptGraph.service.load();

    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: reflections,
          savedReflectionsService: keptGraph.service,
        ),
      ),
    );

    expect(find.text('June 21, 2026'), findsOneWidget);
    final displayedDate = tester.widget<Text>(find.text('June 21, 2026'));
    expect(
      displayedDate.style?.color,
      eastMutedTextColor(tester.element(find.text('June 21, 2026'))),
    );
    // The repository's own `keptAt`-derived display date — never a
    // text/date value fabricated by the test.
    expect(reflections.single.date, 'June 21, 2026');
  });

  testWidgets('Kept screen uses the quiet empty state', (tester) async {
    // Correction: an isolated, empty `KeptRepositoryTestGraph` supplies the
    // service so this screen never falls through to the uninitialized
    // production `app_services.savedReflectionsService`. No production
    // state is fabricated and no bootstrap is called.
    final keptGraph = KeptRepositoryTestGraph();
    await tester.pumpWidget(
      MaterialApp(
        home: SavedReflectionsScreen(
          reflections: const [],
          savedReflectionsService: keptGraph.service,
        ),
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

    await tester.tap(find.byKey(const ValueKey('east-back-button')));
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
    expect(
      calls.single.uri.toString(),
      'https://east.productions/app/privacy',
    );
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

    expect(find.text('This could not be completed. Please try again.'),
        findsOneWidget);
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

    expect(find.text('This could not be completed. Please try again.'),
        findsOneWidget);
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

    expect(find.text('This could not be completed. Please try again.'),
        findsOneWidget);

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

    expect(find.text('This could not be completed. Please try again.'),
        findsOneWidget);
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

    expect(find.text('This could not be completed. Please try again.'),
        findsOneWidget);
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
    expect(find.text('This could not be completed. Please try again.'),
        findsNothing);
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
        label: 'Restore Purchases. Preparing…',
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
