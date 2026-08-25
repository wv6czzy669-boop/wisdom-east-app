import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/bootstrap/bootstrap_gate.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';

void main() {
  testWidgets('pending bootstrap paints a safe waiting surface',
      (tester) async {
    final bootstrap = Completer<void>();
    addTearDown(() {
      if (!bootstrap.isCompleted) bootstrap.complete();
    });

    await tester.pumpWidget(
      BootstrapGate(
        bootstrap: bootstrap.future,
        waitingDisclosureDelay: Duration.zero,
        readyBuilder: (_) => const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('READY'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('EAST.'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.text('READY'), findsNothing);
  });

  testWidgets('builds app content only after the same future completes',
      (tester) async {
    final bootstrap = Completer<void>();
    var readyBuilds = 0;
    await tester.pumpWidget(
      BootstrapGate(
        bootstrap: bootstrap.future,
        readyBuilder: (_) {
          readyBuilds += 1;
          return const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('READY'),
          );
        },
      ),
    );

    expect(readyBuilds, 0);
    bootstrap.complete();
    await tester.pump();

    expect(find.text('READY'), findsOneWidget);
    expect(readyBuilds, 1);
  });

  testWidgets('unexpected failure stays fail-closed and visible',
      (tester) async {
    final bootstrap = Completer<void>();
    await tester.pumpWidget(
      BootstrapGate(
        bootstrap: bootstrap.future,
        readyBuilder: (_) => const Text('MUST NOT BUILD'),
      ),
    );

    bootstrap.completeError(StateError('native channel failure'));
    await tester.pump();

    expect(find.text('MUST NOT BUILD'), findsNothing);
    expect(find.textContaining('taking longer than expected'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });

  testWidgets('long wait discloses recovery without canceling bootstrap',
      (tester) async {
    final bootstrap = Completer<void>();
    await tester.pumpWidget(
      BootstrapGate(
        bootstrap: bootstrap.future,
        waitingDisclosureDelay: Duration.zero,
        longWaitDisclosureDelay: Duration.zero,
        readyBuilder: (_) => const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('READY AFTER WAIT'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.textContaining('taking longer than expected'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);

    bootstrap.complete();
    await tester.pump();
    expect(find.text('READY AFTER WAIT'), findsOneWidget);
  });

  testWidgets('bootstrap recovery follows the resolved product locale',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localeController = LocalePreferenceController();
    await localeController.setExplicitLocale(const Locale('tr'));
    addTearDown(localeController.dispose);
    final bootstrap = Completer<void>();
    addTearDown(() {
      if (!bootstrap.isCompleted) bootstrap.complete();
    });

    await tester.pumpWidget(
      BootstrapGate(
        bootstrap: bootstrap.future,
        localePreferenceController: localeController,
        waitingDisclosureDelay: Duration.zero,
        longWaitDisclosureDelay: Duration.zero,
        readyBuilder: (_) => const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('READY'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.textContaining('beklenenden uzun sürüyor'), findsOneWidget);
    bootstrap.complete();
    await tester.pump();
  });
}
