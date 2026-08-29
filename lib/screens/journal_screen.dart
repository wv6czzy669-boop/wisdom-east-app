import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/favorite_item.dart';
import '../l10n/east_localizations.dart';
import '../services/app_services.dart' as app_services;
import '../services/journal_owner_service.dart';
import '../services/journal_pdf_builder.dart';
import '../services/purchase_service.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../utils/journal_owner_name_policy.dart';
import '../widgets/east_back_button.dart';
import '../widgets/journal_pdf_reader.dart';
import 'keeper_screen.dart';

enum _JournalStage { resolving, generating, preview, error }

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
    this.purchaseService,
    this.journalOwnerService,
    this.pdfBuilder,
    this.shareHandler,
  });

  final List<FavoriteItem> items;
  final bool isKeeper;
  final PurchaseService? purchaseService;
  final JournalOwnerService? journalOwnerService;
  final JournalPdfBuilder? pdfBuilder;
  final JournalShareHandler? shareHandler;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late final JournalOwnerService _ownerService;
  late final PurchaseService _purchaseService;
  late final JournalPdfBuilder? _injectedPdfBuilder;

  _JournalStage _stage = _JournalStage.resolving;
  String? _ownerName;
  Uint8List? _pdfBytes;
  JournalPdfAccessibility? _pdfAccessibility;

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
  Brightness? _generatedBrightness;
  Brightness? _brightnessGenerationInFlight;

  // Real-device repair: the Name edit flow is now the approved full-field
  // decision takeover (same visual system as Reflection's Delete
  // Reflection screen) rather than a rounded AlertDialog. `_nameEditController`
  // is created fresh each time the overlay opens and disposed when it
  // closes and is never left alive once dismissed.
  bool _editingName = false;
  TextEditingController? _nameEditController;

  /// Live, not cached: re-evaluated on every build so returning from the
  /// existing Keeper paywall (opened from [_handleTakeItWithYou] below)
  /// immediately reflects a fresh purchase without requiring Journal to be
  /// reopened -- mirrors `ReflectionScreen`'s own `_isKeeper` pattern.
  bool get _isKeeper => _purchaseService.resolveKeeperAccess(
        unresolvedFallback: widget.isKeeper,
      );

  TextStyle _style(
    double size, {
    Color? color,
    double height = 1.4,
    double letterSpacing = 0.35,
  }) {
    return EastTypography.localized(
      context,
      size: size,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    _ownerService = widget.journalOwnerService ?? JournalOwnerService();
    _purchaseService = widget.purchaseService ?? app_services.purchaseService;
    _purchaseService.addListener(_onKeeperEntitlementChanged);
    _injectedPdfBuilder = widget.pdfBuilder;
    unawaited(_bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_pdfBytes != null &&
        _injectedPdfBuilder == null &&
        brightness != _generatedBrightness &&
        brightness != _brightnessGenerationInFlight) {
      _brightnessGenerationInFlight = brightness;
      unawaited(_generate());
    }
  }

  @override
  void dispose() {
    _purchaseService.removeListener(_onKeeperEntitlementChanged);
    _nameEditController?.dispose();
    super.dispose();
  }

  void _onKeeperEntitlementChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    if (widget.items.isEmpty) {
      // Empty state is handled entirely by `build()` below -- no generation
      // attempt for a meaningless empty PDF.
      return;
    }

    final savedName = await _ownerService.loadName();
    if (!mounted) return;
    _ownerName = savedName;
    await _generate();
  }

  Future<void> _generate() async {
    final generation = ++_generation;
    final brightness = Theme.of(context).brightness;
    _brightnessGenerationInFlight = brightness;
    // Only the very first generation (no publication has ever existed yet)
    // shows the reserved-but-empty "generating" shape -- a regeneration
    // with a prior good preview never reverts away from `preview`, so the
    // existing `PdfPreview` and its already-rastered pages stay mounted and
    // visible for the whole of this call.
    if (_pdfBytes == null) {
      setState(() => _stage = _JournalStage.generating);
    }

    final JournalPdfPublication publication;
    try {
      final locale = Localizations.localeOf(context);
      final pdfBuilder = _injectedPdfBuilder ??
          JournalPdfBuilder(
            localizations: eastLocalizations(context),
            presentation: JournalPdfPresentation(
              locale: locale,
              brightness: brightness,
            ),
          );
      publication = await pdfBuilder.buildPublication(
        items: widget.items,
        ownerName: _ownerName,
      );
    } catch (_) {
      // A generation failure never touches Kept/Reflection/Return/daily
      // state -- `JournalPdfBuilder` only ever reads. Fails calmly here:
      // if a good preview already exists, it is left exactly as-is rather
      // than being replaced by an error state.
      if (!mounted || generation != _generation) return;
      _brightnessGenerationInFlight = null;
      if (_pdfBytes == null) {
        setState(() => _stage = _JournalStage.error);
      }
      return;
    }

    if (!mounted || generation != _generation) return;
    if (_injectedPdfBuilder == null &&
        Theme.of(context).brightness != brightness) {
      _brightnessGenerationInFlight = null;
      unawaited(_generate());
      return;
    }
    setState(() {
      _pdfBytes = publication.bytes;
      _pdfAccessibility = publication.accessibility;
      _previewBuild = (format) async => publication.bytes;
      _generatedBrightness = brightness;
      _brightnessGenerationInFlight = null;
      _stage = _JournalStage.preview;
    });
  }

  void _retryGeneration() {
    if (_stage != _JournalStage.error) return;
    unawaited(_generate());
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
    final nextName =
        JournalOwnerNamePolicy.normalize(_nameEditController?.text);
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
    // Build 33 real-device Voice Control repair: the outer `Semantics`
    // must carry its own `onTap` -- see `_takeItWithYouAction` below for
    // the full explanation of why `ExcludeSemantics` alone left this
    // node with a label and a `button` trait but no real
    // `SemanticsAction.tap`.
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: EastTypography.localized(
                  context,
                  size: 11,
                  color: color,
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
    final l10n = eastLocalizations(context);

    return Positioned.fill(
      child: Container(
        key: const ValueKey('journal-name-decision'),
        color: EastColors.of(context).overlay,
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
                // decision. `MergeSemantics` gives VoiceOver a stable
                // accessible name (see ReflectionScreen's writing area)
                // without reintroducing that visible heading.
                MergeSemantics(
                  child: Semantics(
                    label: l10n.yourName,
                    child: TextField(
                      key: const ValueKey('journal-name-edit-field'),
                      controller: controller,
                      autofocus: true,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          JournalOwnerNamePolicy.maximumGraphemeLength,
                        ),
                      ],
                      textAlign: TextAlign.center,
                      style: _style(26),
                      cursorColor: EastColors.of(context).ink,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.yourName,
                        hintStyle:
                            _style(26, color: EastColors.of(context).hint),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: eastMutedTextColor(context), width: 0.5),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: eastMutedTextColor(context), width: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_ownerName != null) ...[
                      _nameDecisionLabel(
                        l10n.removeUpper,
                        onTap: () => unawaited(_removeNameEdit()),
                        color: EastColors.of(context).secondary,
                      ),
                      const SizedBox(width: 40),
                    ],
                    _nameDecisionLabel(
                      l10n.cancelUpper,
                      onTap: _cancelNameEdit,
                      color: EastColors.of(context).secondary,
                    ),
                    const SizedBox(width: 40),
                    _nameDecisionLabel(
                      l10n.saveUpper,
                      onTap: () => unawaited(_saveNameEdit()),
                      color: EastColors.of(context).ink,
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
    final l10n = eastLocalizations(context);
    return Scaffold(
      backgroundColor: EastColors.of(context).background,
      // Real-device repair: without this, the keyboard's appearance behind
      // the name-decision overlay shrinks this Scaffold's own body height,
      // which reflows *everything* inside it -- both the overlay (see
      // `_nameDecisionOverlay`) and the underlying preview/gate content
      // behind the scrim. Disabling the automatic resize keeps every layer
      // of this screen at a constant height regardless of keyboard state.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: EastColors.of(context).background,
        foregroundColor: EastColors.of(context).ink,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        // Real-device repair: the trailing period is dropped, matching
        // Return's own app-screen title correction.
        title: Text(l10n.journal, style: _style(24)),
        actions: [
          if (_stage == _JournalStage.preview)
            // Build 33 real-device Voice Control repair: same missing-
            // `onTap` defect as `_takeItWithYouAction`/`_nameDecisionLabel`
            // -- fixed the same way.
            Semantics(
              button: true,
              label: _ownerName == null ? l10n.addName : l10n.changeName,
              onTap: _openNameEditor,
              child: ExcludeSemantics(
                child: TextButton(
                  key: const ValueKey('journal-name-action'),
                  onPressed: _openNameEditor,
                  child: Text(
                    l10n.nameUpper,
                    style: _style(
                      11,
                      color: eastMutedTextColor(context),
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
          eastLocalizations(context).nothingHasStayedYet,
          key: const ValueKey('journal-empty-state'),
          style: _style(21, color: eastMutedTextColor(context)),
        ),
      );
    }

    switch (_stage) {
      case _JournalStage.resolving:
        // Near-instantaneous protected local read. Journal never waits for
        // an optional-name decision before it starts preparing.
        return const SizedBox.shrink();
      case _JournalStage.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              key: const ValueKey('journal-error-state'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eastLocalizations(context).journalCouldNotBePrepared,
                  textAlign: TextAlign.center,
                  style: _style(19, color: eastMutedTextColor(context)),
                ),
                const SizedBox(height: 30),
                Semantics(
                  button: true,
                  label: eastLocalizations(context).retry,
                  onTap: _retryGeneration,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      key: const ValueKey('journal-retry-action'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _retryGeneration,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 44, minHeight: 44),
                        child: Center(
                          child: Text(
                            eastLocalizations(context).tryAgainUpper,
                            style: _style(
                              11,
                              color: EastColors.of(context).ink,
                              letterSpacing: 3.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    final accessibility = _pdfAccessibility;
    if (accessibility == null) return const SizedBox.shrink();
    return JournalPdfReader(
      key: const ValueKey('journal-pdf-reader'),
      pages: pages,
      journalLabel: eastLocalizations(context).journal,
      accessibility: accessibility,
    );
  }

  Widget _buildPreviewSurface() {
    final buildCallback = _previewBuild;
    final ready = buildCallback != null;

    return Column(
      children: [
        // The publication begins close to the title. A small breath remains,
        // but the former 28pt dead band is removed so the PDF can occupy the
        // visual field with the confidence of a real reading surface.
        const SizedBox(height: 8),
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
                      BoxDecoration(color: EastColors.of(context).background),
                  loadingWidget: const SizedBox.shrink(),
                  pagesBuilder: _pagesBuilder,
                )
              : const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
        // Build 33 real-device Voice Control repair: the outer `Semantics`
        // previously had no `onTap` of its own -- only the
        // `ExcludeSemantics`-wrapped `GestureDetector` below did, which
        // never reaches the platform. Voice Control's "Tap"/"Show Names"
        // activation relies on the real `SemanticsAction.tap`, so this
        // control was effectively inert to it despite reading correctly
        // to VoiceOver. Fixed by mirroring the same handler on the outer
        // node -- `_handleTakeItWithYou` is idempotent/self-guarding
        // (see its own doc comment), so exposing it here changes nothing
        // about when the action is safe to invoke.
        //
        // For the non-Keeper (gated) state, `_handleTakeItWithYou` is a
        // real action -- it opens the Keeper screen, never a silent
        // no-op -- so a `hint` truthfully describes that outcome without
        // altering the existing visible/spoken label.
        Semantics(
          button: true,
          label: isKeeper
              ? eastLocalizations(context).takeItWithYou
              : eastLocalizations(context).takeItWithYouKeeper,
          hint: isKeeper ? null : eastLocalizations(context).opensKeeper,
          onTap: () => unawaited(_handleTakeItWithYou()),
          child: ExcludeSemantics(
            child: GestureDetector(
              key: const ValueKey('journal-take-action'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_handleTakeItWithYou()),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Text(
                  eastLocalizations(context).takeItWithYou,
                  // Approved "Free state — the gate" direction: touching
                  // this never opens a paywall -- the line itself simply
                  // recedes and "Available with Keeper." answers it below,
                  // in the reading tier. Nothing else moves.
                  //
                  // Build 33 accessibility repair: recedes to 70% opacity,
                  // not ~52% -- 52% measured ~2.95:1 (Light) / ~4.09:1
                  // (Dark) against the main background, both below WCAG
                  // AA's 4.5:1 for normal-sized meaningful text. 70% is the
                  // minimum opacity that clears 4.5:1 in both Light
                  // (~4.75:1) and Dark (~6.32:1) while still reading as
                  // visibly receded/gated next to the fully-opaque Keeper
                  // state -- a local presentation change only, no theme
                  // token touched.
                  style: _style(
                    22,
                    color: isKeeper
                        ? EastColors.of(context).ink
                        : EastColors.of(context).ink.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!isKeeper) ...[
          const SizedBox(height: 6),
          Text(
            eastLocalizations(context).availableWithKeeper,
            key: const ValueKey('journal-keeper-note'),
            style: _style(15),
          ),
        ],
      ],
    );
  }
}
