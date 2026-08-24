import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:wisdom_app/theme/east_design.dart';
import 'package:wisdom_app/widgets/journal_pdf_reader.dart';

void main() {
  final imageBytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      'AAMAASsJTYQAAAAASUVORK5CYII=',
    ),
  );

  List<PdfPreviewPageData> pages(int count) => List.generate(
        count,
        (_) => PdfPreviewPageData(
          image: MemoryImage(imageBytes),
          width: 595,
          height: 842,
        ),
      );

  Future<void> pumpReader(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: eastTheme(brightness: brightness),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 700,
            child: JournalPdfReader(
              pages: pages(4),
              journalLabel: 'Journal',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('presents one A4 page at a time with a quiet folio',
      (tester) async {
    await pumpReader(tester);

    expect(
      find.byKey(const ValueKey('journal-pdf-page-view')),
      findsOneWidget,
    );
    expect(find.text('01  /  04'), findsOneWidget);
    expect(find.byKey(const ValueKey('journal-pdf-page-0')), findsOneWidget);
  });

  testWidgets('horizontal paging advances the folio', (tester) async {
    await pumpReader(tester);

    await tester.drag(
      find.byKey(const ValueKey('journal-pdf-page-view')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('02  /  04'), findsOneWidget);
  });

  testWidgets('page field follows EAST. Dark appearance', (tester) async {
    await pumpReader(tester, brightness: Brightness.dark);

    final page = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('journal-pdf-page-0')),
    );
    final decoration = page.decoration as BoxDecoration;
    expect(decoration.color, EastColorScheme.dark.background);
    expect(
      (decoration.border! as Border).top.color,
      EastColorScheme.dark.divider.withValues(alpha: 0.72),
    );
  });

  testWidgets('each PDF page exposes a localized page-position label',
      (tester) async {
    await pumpReader(tester);
    final semantics = tester.ensureSemantics();

    expect(find.semantics.byLabel('Journal 1 / 4'), findsOneWidget);

    semantics.dispose();
  });
}
