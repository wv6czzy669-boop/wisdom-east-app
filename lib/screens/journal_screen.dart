import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/journal_owner_service.dart';
import '../services/journal_pdf_builder.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';
import 'keeper_screen.dart';

enum _JournalStage { resolving, namePrompt, generating, preview, error }

/// Injection point for the native export action ("Take it with you" for a
/// Keeper) -- defaults to [Printing.sharePdf]. Exposed for tests only,
/// since the real implementation crosses a platform channel.
typedef JournalShareHandler = Future<bool> Function(
  Uint8List bytes,
  String filename,
);

/// EAST. Phase 10 (visual-polish repair) — the dedicated Journal screen: an
/// on-device A4 publication built from the user's own Kept occurrences.
///
/// Openable by BOTH Free and Keeper -- [isKeeper] gates only the "Take it
/// with you" export action inside this screen, never entry into it (see
/// [SavedReflectionsScreen._openJournal], which no longer redirects a Free
/// user to [KeeperScreen] before this screen is even reached). [items] is
/// the same list [SavedReflectionsService.load] already returned; this
/// screen never reloads, mutates, or writes back to Kept/Reflection
/// storage -- Journal is read-only output.
class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.items,
    required this.isKeeper,
    this.journalOwnerService,
    this.pdfBuilder,
    this.shareHandler,
  });

  final List<FavoriteItem> items;
  final bool isKeeper;
  final JournalOwnerService? journalOwnerService;
  final JournalPdfBuilder? pdfBuilder;
  final JournalShareHandler? shareHandler;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late final JournalOwnerService _ownerService;
  late final JournalPdfBuilder _pdfBuilder;
  late final TextEditingController _nameController;

  _JournalStage _stage = _JournalStage.resolving;
  String? _ownerName;
  Uint8List? _pdfBytes;

  // Real-device repair: the Journal preview must never blank/flash on a
  // regeneration that has a prior good publication to keep showing (Name
  // Save with a changed owner, etc). `PdfPreview`'s own `build` callback is
  // only retriggered by the `printing` package when the *function object*
  // it receives changes identity (see `PdfPreviewCustom.didUpdateWidget`) --
  // so `_previewBuild` is a field holding one fixed closure per accepted
  // generation, read (never recreated) on every `build()`. An unrelated
  // `setState` (Name overlay open/close, keyboard inset, etc.) therefore
  // rebuilds this screen without the `PdfPreview` widget seeing a different
  // `build` callback, and the `printing` package never re-rasters. Only
  // `_generate` below reassigns it, and only once new bytes are actually
  // ready -- so the previous field's pages stay visible in the *same*
  // mounted `PdfPreviewCustomState` (never unmounted -- see
  // `_buildPreviewSurface`) until the new ones stream in and replace them,
  // one page at a time.
  Future<Uint8List> Function(PdfPageFormat)? _previewBuild;

  // Discards a generation's result if a newer one has since started --
  // otherwise a slow first regeneration could resolve after a faster
  // second one and stomp it back onto screen (real-device requirement:
  // "only the newest valid publication replaces the visible preview").
  int _generation = 0;

  // Real-device repair: the Name edit flow is now the approved full-field
  // decision takeover (same visual system as Reflection's Delete
  // Reflection screen) rather than a rounded AlertDialog. `_nameEditController`
  // is created fresh each time the overlay opens and disposed when it
  // closes -- never shared with `_nameController` (the separate, first-run
  // name-prompt field), and never left alive once dismissed.
  bool _editingName = false;
  TextEditingController? _nameEditController;

  /// Live, not cached: re-evaluated on every build so returning from the
  /// existing Keeper paywall (opened from [_handleTakeItWithYou] below)
  /// immediately reflects a fresh purchase without requiring Journal to be
  /// reopened -- mirrors `ReflectionScreen`'s own `_isKeeper` pattern.
  bool get _isKeeper =>
      widget.isKeeper || app_services.purchaseService.isKeeper;

  TextStyle _style(
    double size, {
    Color color = EastColors.ink,
    double height = 1.4,
    double letterSpacing = 0.35,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w400,
      fontFamily: EastTypography.fontFamily,
      fontFamilyFallback: EastTypography.fontFamilyFallback,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    _ownerService = widget.journalOwnerService ?? JournalOwnerService();
    _pdfBuilder = widget.pdfBuilder ?? JournalPdfBuilder();
    _nameController = TextEditingController();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameEditController?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.items.isEmpty) {
      // Empty state is handled entirely by `build()` below -- no name
      // prompt, no generation attempt for a meaningless empty PDF.
      return;
    }

    final handled = await _ownerService.hasHandledNamePrompt();
    if (!mounted) return;
    if (!handled) {
      setState(() => _stage = _JournalStage.namePrompt);
      return;
    }

    final savedName = await _ownerService.loadName();
    if (!mounted) return;
    _ownerName = savedName;
    await _generate();
  }

  Future<void> _generate() async {
    final generation = ++_generation;
    // Only the very first generation (no publication has ever existed yet)
    // shows the reserved-but-empty "generating" shape -- a regeneration
    // with a prior good preview never reverts away from `preview`, so the
    // existing `PdfPreview` and its already-rastered pages stay mounted and
    // visible for the whole of this call.
    if (_pdfBytes == null) {
      setState(() => _stage = _JournalStage.generating);
    }

    final Uint8List bytes;
    try {
      bytes = await _pdfBuilder.build(
        items: widget.items,
        ownerName: _ownerName,
      );
    } catch (_) {
      // A generation failure never touches Kept/Reflection/Return/daily
      // state -- `JournalPdfBuilder` only ever reads. Fails calmly here:
      // if a good preview already exists, it is left exactly as-is rather
      // than being replaced by an error state.
      if (!mounted || generation != _generation) return;
      if (_pdfBytes == null) {
        setState(() => _stage = _JournalStage.error);
      }
      return;
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _pdfBytes = bytes;
      _previewBuild = (format) async => bytes;
      _stage = _JournalStage.preview;
    });
  }

  Future<void> _continueFromNamePrompt() async {
    final entered = _nameController.text.trim();
    if (entered.isEmpty) {
      await _ownerService.skip();
      _ownerName = null;
    } else {
      await _ownerService.saveName(entered);
      _ownerName = entered;
    }
    if (!mounted) return;
    await _generate();
  }

  Future<void> _skipNamePrompt() async {
    await _ownerService.skip();
    _ownerName = null;
    if (!mounted) return;
    await _generate();
  }

  /// A quiet, non-settings-screen way to add/change/remove the owner name
  /// later, reachable from the preview stage. Never mandatory, never
  /// nags -- see the class doc comment.
  ///
  /// Real-device repair: presentation only -- opens the approved full-field
  /// decision overlay (see `_nameDecisionOverlay`) instead of a rounded
  /// AlertDialog. Edit/Remove/Cancel/Save semantics, persistence, and
  /// regeneration are unchanged.
  void _openNameEditor() {
    _nameEditController?.dispose();
    _nameEditController = TextEditingController(text: _ownerName ?? '');
    setState(() => _editingName = true);
  }

  void _cancelNameEdit() {
    if (!mounted) return;
    setState(() => _editingName = false);
  }

  Future<void> _saveNameEdit() async {
    final entered = _nameEditController?.text.trim() ?? '';
    final nextName = entered.isEmpty ? null : entered;
    // An unchanged name (including "still empty") must not regenerate the
    // publication at all -- only a genuine change to the owner name is
    // publication-affecting.
    if (nextName == _ownerName) {
      if (!mounted) return;
      setState(() => _editingName = false);
      return;
    }
    if (nextName == null) {
      await _ownerService.clearName();
      _ownerName = null;
    } else {
      await _ownerService.saveName(nextName);
      _ownerName = nextName;
    }
    if (!mounted) return;
    setState(() => _editingName = false);
    await _generate();
  }

  Future<void> _removeNameEdit() async {
    await _ownerService.clearName();
    _ownerName = null;
    if (!mounted) return;
    setState(() => _editingName = false);
    await _generate();
  }

  /// The single intentional export entry point ("Take it with you"). Free:
  /// opens the existing Keeper paywall -- never a second/custom one. Keeper:
  /// invokes the native share sheet directly for the already-generated PDF.
  /// [PdfPreview] below has its own built-in sharing disabled entirely (see
  /// `_buildBody`'s preview case), so this is the only path that can ever
  /// export the Journal, for either entitlement.
  Future<void> _handleTakeItWithYou() async {
    if (!_isKeeper) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (context) => const KeeperScreen(),
        ),
      );
      // A fresh purchase inside the paywall is picked up by `_isKeeper`'s
      // live re-evaluation -- rebuild so "Available with Keeper." and the
      // action's own behavior reflect it immediately, with no need to
      // reopen Journal.
      if (mounted) setState(() {});
      return;
    }

    final bytes = _pdfBytes;
    if (bytes == null) return;
    try {
      final share = widget.shareHandler ?? _defaultShare;
      await share(bytes, 'Journal.pdf');
    } catch (_) {
      // A share-sheet failure is non-critical -- the Journal itself
      // remains fully generated and readable; no retry UI required for a
      // system sheet the user can simply invoke again.
    }
  }

  static Future<bool> _defaultShare(Uint8List bytes, String filename) {
    return Printing.sharePdf(bytes: bytes, filename: filename);
  }

  Widget _nameDecisionLabel(
    String label, {
    required VoidCallback? onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  fontFamily: EastTypography.fontFamily,
                  fontFamilyFallback: EastTypography.fontFamilyFallback,
                  letterSpacing: 3.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Real-device repair: the approved full-field decision takeover for
  /// editing the Journal owner name -- same visual system as Reflection's
  /// Delete Reflection screen (quiet editorial composition, the surface
  /// beneath strongly dimmed, no rounded modal/card/system-alert
  /// appearance). Edit current name / Remove / Cancel / Save all keep
  /// their exact existing meaning and persistence; only the presentation
  /// changed.
  Widget _nameDecisionOverlay() {
    if (!_editingName) return const SizedBox.shrink();
    final controller = _nameEditController!;

    return Positioned.fill(
      child: Container(
        key: const ValueKey('journal-name-decision'),
        color: EastColors.overlay,
        child: SafeArea(
          // Real-device repair: `Center` used to position this composition
          // relative to the *available* body height, which changes when
          // the keyboard opens/closes (via `Scaffold`'s own bottom-inset
          // resize) -- so the whole block visibly jumped as the keyboard
          // animated. Anchoring to a fixed offset from the top instead
          // keeps the name field and the REMOVE/CANCEL/SAVE row on the
          // exact same visual axis regardless of keyboard state; the
          // `SingleChildScrollView` only ever engages as a safety net (a
          // very small screen or a large accessibility text scale), never
          // as the normal path.
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              34,
              140,
              34,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Real-device repair: the "Journal name" heading is
                // removed entirely -- the name itself, not a label
                // describing it, is the clear focus of this full-field
                // decision.
                TextField(
                  key: const ValueKey('journal-name-edit-field'),
                  controller: controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: _style(26),
                  cursorColor: EastColors.ink,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Your name',
                    hintStyle: _style(26, color: EastColors.hint),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: eastMutedTextColor, width: 0.5),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: eastMutedTextColor, width: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_ownerName != null) ...[
                      _nameDecisionLabel(
                        'REMOVE',
                        onTap: () => unawaited(_removeNameEdit()),
                        color: EastColors.secondary,
                      ),
                      const SizedBox(width: 40),
                    ],
                    _nameDecisionLabel(
                      'CANCEL',
                      onTap: _cancelNameEdit,
                      color: EastColors.secondary,
                    ),
                    const SizedBox(width: 40),
                    _nameDecisionLabel(
                      'SAVE',
                      onTap: () => unawaited(_saveNameEdit()),
                      color: EastColors.ink,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EastColors.background,
      // Real-device repair: without this, the keyboard's appearance behind
      // the name-decision overlay shrinks this Scaffold's own body height,
      // which reflows *everything* inside it -- both the overlay (see
      // `_nameDecisionOverlay`) and the underlying preview/gate content
      // behind the scrim. Disabling the automatic resize keeps every layer
      // of this screen at a constant height regardless of keyboard state;
      // the one flow that genuinely wants keyboard-avoidance (the
      // first-run name prompt) now does it itself, explicitly, in
      // `_buildNamePrompt`.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: EastColors.background,
        foregroundColor: EastColors.ink,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        // Real-device repair: the trailing period is dropped, matching
        // Return's own app-screen title correction.
        title: Text('Journal', style: _style(24)),
        actions: [
          if (_stage == _JournalStage.preview)
            Semantics(
              button: true,
              label: _ownerName == null ? 'Add name' : 'Change name',
              child: ExcludeSemantics(
                child: TextButton(
                  key: const ValueKey('journal-name-action'),
                  onPressed: _openNameEditor,
                  child: Text(
                    'NAME',
                    style: _style(
                      11,
                      color: eastMutedTextColor,
                      letterSpacing: 2.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            IgnorePointer(
              ignoring: _editingName,
              child: _buildBody(context),
            ),
            _nameDecisionOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          'Nothing has stayed yet.',
          key: const ValueKey('journal-empty-state'),
          style: _style(21, color: eastMutedTextColor),
        ),
      );
    }

    switch (_stage) {
      case _JournalStage.resolving:
        // Near-instantaneous (a single local preferences read) -- kept
        // blank rather than pre-committing to either the name-prompt or
        // preview shape, so a first-run user never sees a shape swap that
        // was never going to be theirs.
        return const SizedBox.shrink();
      case _JournalStage.namePrompt:
        return _buildNamePrompt();
      case _JournalStage.error:
        return Center(
          child: Text(
            'Journal could not be prepared. Please try again.',
            key: const ValueKey('journal-error-state'),
            textAlign: TextAlign.center,
            style: _style(19, color: eastMutedTextColor),
          ),
        );
      case _JournalStage.generating:
      case _JournalStage.preview:
        // Real-device repair: from the moment generation begins, the exact
        // same shape (top gap, reserved preview geometry, reserved action
        // row) is rendered whether or not the PDF is ready yet -- only the
        // *content* inside that reserved geometry swaps once it is. This
        // is what removes the real-device Kept -> Journal transition
        // defect: no collapsing-to-blank body, no late layout
        // reconstruction, no generic loading indicator competing with the
        // publication.
        return _buildPreviewSurface();
    }
  }

  static const _previewPageMargin = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 14,
  );

  // Real-device repair: the `printing` package's own default page widget
  // (`PdfPreviewPage`) decorates every page with a white, drop-shadowed
  // card -- meant for its light default theme, never overridden by this
  // screen's own `scrollViewDecoration` (which only paints the *scroll
  // background* behind pages, not each page itself). Since every actual
  // page in the generated PDF is already full-bleed stone (see
  // `JournalPdfBuilder`), that white card is never the publication's own
  // content -- it is a full A4-sized white rectangle that only ever
  // appears for the one frame before the page's rasterized image has
  // decoded. This `pagesBuilder` replaces that page chrome with the
  // screen's own stone, shadowless surface (so that one frame is
  // indistinguishable from the surrounding screen) and renders each page's
  // `Image` with `gaplessPlayback: true` -- when a regeneration replaces a
  // page's `ImageProvider` with a new one, the previously decoded frame
  // stays painted until the new one finishes decoding, instead of the
  // `Image` widget clearing to nothing in between.
  Widget _pagesBuilder(BuildContext context, List<PdfPreviewPageData> pages) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        return Container(
          margin: _previewPageMargin,
          color: EastColors.background,
          child: AspectRatio(
            aspectRatio: page.aspectRatio,
            child: Image(
              image: page.image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewSurface() {
    final buildCallback = _previewBuild;
    final ready = buildCallback != null;

    return Column(
      children: [
        // Real-device repair: "Gather what you kept." removed entirely
        // (approved direction: nothing outranks the publication, and a
        // line that only describes the object beneath it is noise) --
        // a deliberate 28pt of air replaces it rather than leaving a
        // dead gap, so the page itself sits closer to the title.
        const SizedBox(height: 28),
        // The real A4 Journal preview is the visual hero of this screen --
        // no file-manager chrome, no built-in share/print controls
        // (`useActions: false` removes the entire action bar): the single
        // intentional export entry is "Take it with you." below, never
        // this preview. While the PDF is still generating, this reserved
        // area stays visually quiet (the screen's own stone, nothing
        // else) rather than showing any progress/loading treatment --
        // `loadingWidget` is also pinned to the same quiet emptiness so
        // the `printing` package's own default spinner never appears
        // during the preview's own internal page rendering.
        //
        // Real-device repair: this `PdfPreview` is only ever absent before
        // the *first* publication has ever been generated -- once `ready`
        // goes true for the first time, it stays mounted (same `ValueKey`,
        // same `PdfPreviewCustomState`) for the rest of this screen's
        // lifetime, including through every later regeneration. That is
        // what lets a regeneration's still-visible old pages remain on
        // screen while new ones stream in, rather than the whole preview
        // collapsing to blank and popping back once new bytes exist.
        Expanded(
          child: ready
              ? PdfPreview.builder(
                  key: const ValueKey('journal-pdf-preview'),
                  build: buildCallback,
                  initialPageFormat: PdfPageFormat.a4,
                  pageFormats: const {'A4': PdfPageFormat.a4},
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: false,
                  allowSharing: false,
                  useActions: false,
                  pdfFileName: 'Journal.pdf',
                  scrollViewDecoration:
                      const BoxDecoration(color: EastColors.background),
                  loadingWidget: const SizedBox.shrink(),
                  pagesBuilder: _pagesBuilder,
                )
              : const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          child: AnimatedOpacity(
            key: const ValueKey('journal-take-action-reveal'),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            opacity: ready ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !ready,
              child: _takeItWithYouAction(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _takeItWithYouAction() {
    final isKeeper = _isKeeper;
    return Column(
      children: [
        Semantics(
          button: true,
          label: isKeeper
              ? 'Take it with you.'
              : 'Take it with you. Available with Keeper.',
          child: ExcludeSemantics(
            child: GestureDetector(
              key: const ValueKey('journal-take-action'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_handleTakeItWithYou()),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Text(
                  'Take it with you.',
                  // Approved "Free state — the gate" direction: touching
                  // this never opens a paywall -- the line itself simply
                  // recedes to ~52% and "Available with Keeper." answers
                  // it below, in the reading tier. Nothing else moves.
                  style: _style(
                    22,
                    color: isKeeper
                        ? EastColors.ink
                        : EastColors.ink.withValues(alpha: 0.52),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!isKeeper) ...[
          const SizedBox(height: 6),
          Text(
            'Available with Keeper.',
            key: const ValueKey('journal-keeper-note'),
            style: _style(15),
          ),
        ],
      ],
    );
  }

  Widget _buildNamePrompt() {
    return SingleChildScrollView(
      // Real-device repair: with the Scaffold's own automatic resize now
      // disabled (see `build`), this is the one Journal flow that still
      // wants ordinary keyboard-avoidance -- so it does it itself here,
      // explicitly, exactly like `ReflectionScreen`'s writing area already
      // does.
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        32 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Whose journal is this?', style: _style(24)),
          const SizedBox(height: 10),
          Text(
            'Only kept on this device.',
            style: _style(16, color: eastMutedTextColor),
          ),
          const SizedBox(height: 34),
          TextField(
            key: const ValueKey('journal-name-field'),
            controller: _nameController,
            autofocus: false,
            style: _style(20),
            cursorColor: EastColors.ink,
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: _style(20, color: EastColors.hint),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: eastMutedTextColor, width: 0.5),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: eastMutedTextColor, width: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 34),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('journal-name-skip'),
                onPressed: () => unawaited(_skipNamePrompt()),
                child: Text('Skip', style: _style(17)),
              ),
              const SizedBox(width: 14),
              TextButton(
                key: const ValueKey('journal-name-continue'),
                onPressed: () => unawaited(_continueFromNamePrompt()),
                child: Text(
                  'Continue',
                  style: _style(17, color: eastMutedTextColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
