import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';

void main() {
  testWidgets('Keeper screen uses only the locked product message',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    const lockedCopy = [
      'Keeper',
      'Keep what stays.',
      'Enter the Circle',
      'Preserve what stays with you.',
      'Help keep EAST. alive.',
    ];

    for (final line in lockedCopy) {
      expect(find.text(line), findsOneWidget);
    }

    final renderedCopy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toSet();
    expect(renderedCopy, lockedCopy.toSet());
  });

  testWidgets('Keeper screen remains stable on iPhone SE with large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      const MaterialApp(home: KeeperScreen()),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Keeper'), findsOneWidget);
    expect(find.text('Help keep EAST. alive.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
