import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/services/journal_owner_service.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';

/// Real-device repair: the Journal preview must never blank/flash back to
/// an empty or default-white state while a regeneration (Name Save with a
/// changed owner, etc) is in flight -- the previous publication has to stay
/// on screen until the replacement is genuinely ready. These tests prove
/// that invariant with a deliberately slow, individually-gated PDF builder
/// so each generation's readiness is entirely under test control -- never
/// an arbitrary `Duration` guess.
///
/// Delegates to a real [JournalPdfBuilder] once released, so the produced
/// bytes are never faked -- two different owner names always produce two
/// genuinely different byte sequences, which is what lets these tests tell
/// "old preview" and "new preview" apart without inspecting rendered
/// pixels (the `printing` package's own raster pipeline never completes
/// under the plain `flutter test` host -- see the "never fully quiesces"
/// note already established in journal_screen_test.dart -- so assertions
/// here work directly against the generated PDF bytes bound to
/// `PdfPreview.build`, which is exactly the content the package would
/// rasterize and display).
class _SequencedPdfBuilder implements JournalPdfBuilder {
  _SequencedPdfBuilder() : _delegate = JournalPdfBuilder();

  final JournalPdfBuilder _delegate;
  final List<Completer<void>> gates = [];
  // The `pdf` package embeds a wall-clock-derived id/timestamp on every
  // `Document.save()`, so two independently generated documents are never
  // byte-identical even for identical content -- `results` instead records
  // each call's own actual produced bytes (keyed by call index, since two
  // gated calls can resolve out of call order), so tests can compare the
  // currently-displayed preview against the one real generation that
  // should be showing, not a freshly rebuilt (and therefore always
  // different) reference.
  final Map<int, Uint8List> results = {};
  int calls = 0;

  @override
  Future<Uint8List> build({
    required List<FavoriteItem> items,
    String? ownerName,
    DateTime? now,
    bool compress = true,
  }) async {
    final gate = Completer<void>();
    final index = calls;
    gates.add(gate);
    calls++;
    await gate.future;
    final bytes = await _delegate.build(
      items: items,
      ownerName: ownerName,
      now: now,
      compress: compress,
    );
    results[index] = bytes;
    return bytes;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  FavoriteItem item() {
    return FavoriteItem(
      id: '1',
      revealId: 'r-1',
      text: 'A kept wisdom.',
      date: 'August 1, 2026',
      keptAt: DateTime.utc(2026, 7, 1).toIso8601String(),
    );
  }

  /// Reads the bytes currently bound to the mounted `PdfPreview`'s own
  /// `build` callback -- i.e. exactly what the `printing` package would
  /// rasterize and display right now, regardless of whether its own
  /// internal raster pipeline ever completes in this test host.
  Future<Uint8List> currentPreviewBytes(WidgetTester tester) async {
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    return await preview.build(PdfPageFormat.a4);
  }

  Future<void> openNameEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('journal-name-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> saveName(WidgetTester tester, String name) async {
    await tester.enterText(
      find.byKey(const ValueKey('journal-name-edit-field')),
      name,
    );
    await tester.tap(find.text('SAVE'));
    await tester.pump();
  }

  testWidgets(
      'CASE 2/4 -- an existing preview keeps its own bytes visible while a '
      'regeneration is in flight, and PdfPreview is never unmounted to '
      'reach the replacement', (tester) async {
    final builder = _SequencedPdfBuilder();
    final ownerService = JournalOwnerService();
    await ownerService.saveName('Original Name');

    await tester.pumpWidget(
      MaterialApp(
        home: JournalScreen(
          items: [item()],
          isKeeper: true,
          journalOwnerService: ownerService,
          pdfBuilder: builder,
        ),
      ),
    );
    await tester.pump();
    builder.gates[0].complete(); // first generation ready
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PdfPreview), findsOneWidget);
    final firstBytes = await currentPreviewBytes(tester);
    final statePreRegen =
        tester.state<PdfPreviewCustomState>(find.byType(PdfPreviewCustom));

    await openNameEditor(tester);
    await saveName(tester, 'Renamed Owner');
    // The regeneration (builder call #2) is now gated open -- deliberately
    // held so the "in-flight" window is entirely under test control.
    expect(builder.calls, 2);

    // While the replacement is still generating, the preview must not have
    // collapsed to blank/unmounted, and must still show the OLD bytes.
    expect(find.byType(PdfPreview), findsOneWidget);
    expect(
      tester.state<PdfPreviewCustomState>(find.byType(PdfPreviewCustom)),
      same(statePreRegen),
    );
    expect(await currentPreviewBytes(tester), firstBytes);

    builder.gates[1].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The replacement is ready -- it now replaces the old bytes, still
    // without ever having unmounted the preview.
    expect(find.byType(PdfPreview), findsOneWidget);
    expect(
      tester.state<PdfPreviewCustomState>(find.byType(PdfPreviewCustom)),
      same(statePreRegen),
    );
    final secondBytes = await currentPreviewBytes(tester);
    expect(secondBytes, isNot(firstBytes));
  });

  testWidgets(
      'CASE 3 -- opening and cancelling Journal Name never calls the PDF '
      'builder again', (tester) async {
    final builder = _SequencedPdfBuilder();
    final ownerService = JournalOwnerService();
    await ownerService.saveName('Original Name');

    await tester.pumpWidget(
      MaterialApp(
        home: JournalScreen(
          items: [item()],
          isKeeper: true,
          journalOwnerService: ownerService,
          pdfBuilder: builder,
        ),
      ),
    );
    await tester.pump();
    builder.gates[0].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(builder.calls, 1);

    await openNameEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('journal-name-edit-field')),
      'Never used',
    );
    await tester.tap(find.text('CANCEL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(builder.calls, 1);
  });

  testWidgets(
      'SAVE with the unchanged name does not regenerate the publication',
      (tester) async {
    final builder = _SequencedPdfBuilder();
    final ownerService = JournalOwnerService();
    await ownerService.saveName('Original Name');

    await tester.pumpWidget(
      MaterialApp(
        home: JournalScreen(
          items: [item()],
          isKeeper: true,
          journalOwnerService: ownerService,
          pdfBuilder: builder,
        ),
      ),
    );
    await tester.pump();
    builder.gates[0].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(builder.calls, 1);

    await openNameEditor(tester);
    await saveName(tester, 'Original Name');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(builder.calls, 1);
    expect(
      find.byKey(const ValueKey('journal-name-decision')),
      findsNothing,
    );
  });

  testWidgets(
      'CASE 5 -- rapidly opening/cancelling the name editor several times '
      'in a row leaves the preview mounted throughout, with no blank leak',
      (tester) async {
    final builder = _SequencedPdfBuilder();
    final ownerService = JournalOwnerService();
    await ownerService.skip();

    await tester.pumpWidget(
      MaterialApp(
        home: JournalScreen(
          items: [item()],
          isKeeper: true,
          journalOwnerService: ownerService,
          pdfBuilder: builder,
        ),
      ),
    );
    await tester.pump();
    builder.gates[0].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final statePreLoop =
        tester.state<PdfPreviewCustomState>(find.byType(PdfPreviewCustom));

    for (var i = 0; i < 4; i++) {
      await openNameEditor(tester);
      await tester.tap(find.text('CANCEL'));
      await tester.pump();

      expect(find.byType(PdfPreview), findsOneWidget);
      expect(
        tester.state<PdfPreviewCustomState>(find.byType(PdfPreviewCustom)),
        same(statePreLoop),
      );
    }

    expect(builder.calls, 1);
  });

  testWidgets(
      'CASE 6 -- a slow, superseded generation cannot race back onto '
      'screen after a newer one has already completed', (tester) async {
    final builder = _SequencedPdfBuilder();
    final ownerService = JournalOwnerService();
    await ownerService.saveName('Original Name');

    await tester.pumpWidget(
      MaterialApp(
        home: JournalScreen(
          items: [item()],
          isKeeper: true,
          journalOwnerService: ownerService,
          pdfBuilder: builder,
        ),
      ),
    );
    await tester.pump();
    builder.gates[0].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Trigger a first regeneration ("First") -- left gated, i.e. slow.
    await openNameEditor(tester);
    await saveName(tester, 'First');
    await tester.pump();

    // Before it resolves, trigger a second regeneration ("Second").
    await openNameEditor(tester);
    await saveName(tester, 'Second');
    await tester.pump();
    expect(builder.calls, 3);

    // The newer request ("Second", call #2) resolves first.
    builder.gates[2].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(await currentPreviewBytes(tester), equals(builder.results[2]));

    // The stale, slower "First" request (call #1) now resolves late -- it
    // must be discarded rather than stomping "Second" back onto screen.
    builder.gates[1].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(builder.results[1], isNotNull); // the stale call did resolve
    expect(await currentPreviewBytes(tester), equals(builder.results[2]));
  });

  testWidgets(
      'CASE 1 -- first entry never exposes a spinner or default loading '
      'widget while the very first publication is generating',
      (tester) async {
    final builder = _SequencedPdfBuilder();
    final ownerService = JournalOwnerService();
    await ownerService.skip();

    await tester.pumpWidget(
      MaterialApp(
        home: JournalScreen(
          items: [item()],
          isKeeper: true,
          journalOwnerService: ownerService,
          pdfBuilder: builder,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PdfPreview), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(ProgressIndicator), findsNothing);

    builder.gates[0].complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PdfPreview), findsOneWidget);
  });
}
