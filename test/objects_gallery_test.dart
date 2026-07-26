import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/objects_catalog.dart';
import 'package:wisdom_app/screens/objects_screen.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';
import 'package:wisdom_app/widgets/objects/tshirt_color_selector.dart';

/// Finds the `Semantics` widget carrying [label] using a normal
/// element-tree [Finder], so it can be passed to widget-test APIs such as
/// `tester.tap(...)` that require a `FinderBase<Element>` — unlike
/// `find.semantics.byLabel(...)`, which returns a semantics-tree-only
/// finder meant for accessibility assertions (`evaluate()`, `expect(...,
/// findsOneWidget)`), not for driving taps.
Finder _controlLabeled(String label) {
  return find.byWidgetPredicate(
    (Widget widget) => widget is Semantics && widget.properties.label == label,
  );
}

void main() {
  testWidgets(
      'Espresso is selected by default and its gallery starts on image 1',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: ObjectsScreen()),
      );

      expect(
        find.semantics
            .byLabel('${ObjectsCatalog.tshirtName}, Espresso, image 1 of 2'),
        findsOneWidget,
      );
      final espressoNode =
          find.semantics.byLabel('Espresso color').evaluate().single;
      expect(
        espressoNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      final khakiNode = find.semantics.byLabel('Khaki color').evaluate().single;
      expect(
        khakiNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Espresso and Khaki gallery asset order is exact, exactly two '
      'images each', (tester) async {
    expect(ObjectsCatalog.espressoGallery, [
      'assets/objects/espresso_1.webp',
      'assets/objects/espresso_2.webp',
    ]);
    expect(ObjectsCatalog.khakiGallery, [
      'assets/objects/khaki_1.webp',
      'assets/objects/khaki_2.webp',
    ]);
    expect(ObjectsCatalog.espressoGallery, hasLength(2));
    expect(ObjectsCatalog.khakiGallery, hasLength(2));
    for (final path in [
      ...ObjectsCatalog.espressoGallery,
      ...ObjectsCatalog.khakiGallery,
    ]) {
      expect(path, isNot(contains('espresso_3')));
      expect(path, isNot(contains('khaki_3')));
    }
  });

  testWidgets('color buttons render the uploaded optimized button assets',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    final images = tester.widgetList<Image>(
      find.descendant(
        of: find.byType(TshirtColorSelector),
        matching: find.byType(Image),
      ),
    );
    final assetNames =
        images.map((image) => (image.image as AssetImage).assetName).toSet();

    expect(
      assetNames,
      {
        ObjectsCatalog.espressoButtonAsset,
        ObjectsCatalog.khakiButtonAsset,
      },
    );
  });

  testWidgets('changing to Khaki resets to Khaki image 1, and back again',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: ObjectsScreen()),
      );

      // Swipe the T-Shirt gallery forward before switching colors, so a
      // naive implementation that preserved page index would land on
      // Khaki's 2nd image instead of resetting to its 1st.
      await tester.fling(
        find.byType(PageView).first,
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      await tester.tap(_controlLabeled('Khaki color'));
      await tester.pumpAndSettle();

      expect(
        find.semantics
            .byLabel('${ObjectsCatalog.tshirtName}, Khaki, image 1 of 2'),
        findsOneWidget,
      );
      final khakiNode = find.semantics.byLabel('Khaki color').evaluate().single;
      expect(
        khakiNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );

      await tester.fling(
        find.byType(PageView).first,
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      await tester.tap(_controlLabeled('Espresso color'));
      await tester.pumpAndSettle();

      expect(
        find.semantics
            .byLabel('${ObjectsCatalog.tshirtName}, Espresso, image 1 of 2'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('swiping the T-Shirt gallery does not change the selected color',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: ObjectsScreen()),
      );

      await tester.fling(
        find.byType(PageView).first,
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      final espressoNode =
          find.semantics.byLabel('Espresso color').evaluate().single;
      expect(
        espressoNode.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        find.semantics
            .byLabel('${ObjectsCatalog.tshirtName}, Khaki, image 1 of 2'),
        findsNothing,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'the T-Shirt gallery remains a stable two-image loop: 1 -> 2 -> back to 1',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: ObjectsScreen()),
      );

      final gallery = find.byType(PageView).first;
      await tester.fling(gallery, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(
        find.semantics
            .byLabel('${ObjectsCatalog.tshirtName}, Espresso, image 2 of 2'),
        findsOneWidget,
      );

      await tester.fling(gallery, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(
        find.semantics
            .byLabel('${ObjectsCatalog.tshirtName}, Espresso, image 1 of 2'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('gallery images use a non-cropping fit', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    final galleryImages = tester.widgetList<Image>(
      find.descendant(
        of: find.byType(PageView),
        matching: find.byType(Image),
      ),
    );
    expect(galleryImages, isNotEmpty);
    for (final image in galleryImages) {
      expect(image.fit, BoxFit.contain);
    }
  });

  testWidgets(
      'Tote gallery order is exactly Tote2, Tote1 and has no color controls',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      expect(ObjectsCatalog.toteGallery, [
        'assets/objects/tote_1.webp', // Tote2.png
        'assets/objects/tote_2.webp', // Tote1.png
      ]);
      expect(ObjectsCatalog.toteGallery, hasLength(2));

      await tester.pumpWidget(
        const MaterialApp(home: ObjectsScreen()),
      );

      expect(
        find.semantics.byLabel('${ObjectsCatalog.toteName}, image 1 of 2'),
        findsOneWidget,
      );
      expect(find.byType(TshirtColorSelector), findsOneWidget);
      // Only two color controls exist on the whole screen, both for the
      // T-Shirt; none are duplicated near the Tote gallery.
      expect(find.semantics.byLabel('Espresso color'), findsOneWidget);
      expect(find.semantics.byLabel('Khaki color'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'the Tote gallery remains a stable two-image loop: 1 -> 2 -> back to 1',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MaterialApp(home: ObjectsScreen()),
      );

      final toteGallery = find.byKey(const ValueKey('objects-tote-gallery'));
      await tester.ensureVisible(toteGallery);
      await tester.pumpAndSettle();

      await tester.fling(toteGallery, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('${ObjectsCatalog.toteName}, image 2 of 2'),
        findsOneWidget,
      );

      await tester.fling(toteGallery, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(
        find.semantics.byLabel('${ObjectsCatalog.toteName}, image 1 of 2'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'exactly one thin muted divider separates the Tote gallery from the '
      'Discover action, with no enclosing box around the CTA',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ObjectsScreen()),
    );

    final discoverAction =
        find.byKey(const ValueKey('objects-discover-action'));
    await tester.ensureVisible(discoverAction);
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsOneWidget);
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.color, eastMutedTextColor.withValues(alpha: 0.30));

    expect(
      tester.getTopLeft(find.byType(Divider)).dy,
      lessThan(tester.getTopLeft(discoverAction).dy),
    );

    final ctaText = tester.widget<Text>(
      find.descendant(
        of: discoverAction,
        matching: find.text('DISCOVER THE OBJECTS'),
      ),
    );
    expect(ctaText.style?.color, eastMutedTextColor);

    // No enclosing box: the CTA's only ancestors up to the discover key are
    // plain layout widgets, never a decorated Container/Card/Material box.
    expect(
      find.descendant(
        of: discoverAction,
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration != null,
        ),
      ),
      findsNothing,
    );
  });
}
