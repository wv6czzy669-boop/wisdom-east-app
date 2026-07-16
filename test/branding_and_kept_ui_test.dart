import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/services/purchase_service.dart';

void main() {
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

  testWidgets('Kept omits the stored year without changing its data',
      (tester) async {
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

    expect(find.text('June 21'), findsOneWidget);
    expect(find.text(storedDate), findsNothing);
    final displayedDate = tester.widget<Text>(find.text('June 21'));
    expect(displayedDate.style?.color, const Color(0x91FFFFFF));
    expect(reflection.date, storedDate);
  });

  testWidgets('Kept screen uses the new feature title', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SavedReflectionsScreen(reflections: []),
      ),
    );

    expect(find.text('Kept'), findsOneWidget);
    expect(find.text('Nothing kept yet.'), findsOneWidget);
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

  testWidgets('rapid Keeper taps push only one Keeper route', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen()),
    );

    final keeperRow = find.text('Keeper');
    final keeperTapTarget = tester.widget<InkWell>(
      find.ancestor(of: keeperRow, matching: find.byType(InkWell)),
    );
    keeperTapTarget.onTap!();
    keeperTapTarget.onTap!();
    await tester.pumpAndSettle();

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

    await tester.tap(find.text('Privacy Policy'));
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

    await tester.tap(find.text('Privacy Policy'));
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

    await tester.tap(find.text('Privacy Policy'));
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

    await tester.tap(find.text('Reach Out'));
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.uri.scheme, 'mailto');
    expect(calls.single.uri.path, 'dailywisdomeast@gmail.com');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Reach Out launch false or throw shows feedback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          urlLauncher: (uri, {required mode}) async => false,
        ),
      ),
    );

    await tester.tap(find.text('Reach Out'));
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

    await tester.tap(find.text('Reach Out'));
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

    final privacyInkWell = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('Privacy Policy'),
        matching: find.byType(InkWell),
      ),
    );
    privacyInkWell.onTap!();
    privacyInkWell.onTap!();
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

    await tester.tap(find.text('Privacy Policy'));
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

      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();

      _expectSemanticNode(
        label: 'Privacy Policy. Opening.',
        isButton: true,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );

      await tester.tap(find.text('Privacy Policy'));
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

      await tester.tap(find.text('Reach Out'));
      await tester.pump();

      _expectSemanticNode(
        label: 'Reach Out. Opening.',
        isButton: true,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );

      await tester.tap(find.text('Reach Out'));
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
