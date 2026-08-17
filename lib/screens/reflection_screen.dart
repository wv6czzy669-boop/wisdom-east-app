import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/favorite_item.dart';
import '../services/app_services.dart' as app_services;
import '../services/saved_reflections_service.dart';
import '../theme/muted_text_color.dart';
import '../utils/kept_diagnostics.dart';
import '../utils/reflection_prompt.dart';
import '../widgets/east_back_button.dart';

class ReflectionScreen extends StatefulWidget {
  const ReflectionScreen({
    super.key,
    required this.item,
    required this.isKeeper,
    this.savedReflectionsService,
    this.autosaveDebounce = const Duration(milliseconds: 600),
  });

  final FavoriteItem item;
  final bool isKeeper;
  final SavedReflectionsService? savedReflectionsService;

  /// How long typing must pause before the current text is autosaved and
  /// (if it actually changed) becomes eligible for the next coalesced
  /// CloudKit sync attempt. Exposed for tests only — production always uses
  /// the default.
  final Duration autosaveDebounce;

  @override
  State<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends State<ReflectionScreen>
    with WidgetsBindingObserver {
  // Real-device diagnostic pass (Phase 8/root-cause repair): every
  // `keptDiagnostic(...)` call in this file (pop-requested/flush-begin/
  // local-write-begin/success/limit-reached/failed/exhausted/pop-allowed/
  // pop-blocked) is a permanent, low-volume, privacy-safe failure/outcome
  // trace, per `lib/utils/kept_diagnostics.dart`'s own established
  // contract: debug-build-only, content-free (stage names, attempt
  // numbers, and exception *types* only -- never wisdom or Reflection
  // text). The higher-volume per-keystroke/per-revision investigation
  // instrumentation used to root-cause the false-success in-flight-Future
  // bug (text-change/debounce-scheduled/debounce-fired/persist-requested/
  // flush-awaiting-inflight/persist-complete, and the extra debug-only
  // authoritative-readback disk read) has been removed now that the bug
  // is fixed and verified -- see the fix itself, `_persist`/
  // `_runPersistLoop`, for why correctness no longer depends on it.
  late final TextEditingController _controller;
  late final SavedReflectionsService _service;
  late final String _prompt;

  Timer? _debounceTimer;

  /// The active drain loop, if one is currently running -- represents
  /// "keep attempting persistence until every edit revision requested so
  /// far is durably committed," never merely "one attempt is in flight."
  /// Cleared exclusively via the `.whenComplete()` callback attached in
  /// [_persist] (see that method's own doc comment for why this ordering
  /// is load-bearing), never from inside [_runPersistLoop]'s own body --
  /// that is precisely the ordering bug root-cause repair below fixes.
  Future<void>? _inFlightPersist;
  bool _persistPending = false;
  String? _lastPersistedText;
  bool _deleteInProgress = false;
  bool _confirmingDelete = false;

  /// Root-cause repair: monotonic revision accounting so "persistence
  /// succeeded" has one precise, unambiguous meaning -- "every edit up to
  /// the revision this specific caller requested is durably committed to
  /// the authoritative local repository" -- never merely "a drain loop
  /// existed and finished" or "an earlier revision succeeded." [_editRevision]
  /// increments on every real text change; [_persistedRevision] only ever
  /// advances to a revision [_runPersistLoop] has itself just confirmed is
  /// either genuinely unchanged (nothing to persist) or freshly, durably
  /// written. A caller's own success is `_persistedRevision >=` the
  /// revision it captured at its own call time -- see [_persist].
  int _editRevision = 0;
  int _persistedRevision = 0;

  bool get _isKeeper =>
      widget.isKeeper || app_services.purchaseService.isKeeper;

  TextStyle _style(
    double size, {
    Color color = const Color(0xFFF4F0E8),
    double height = 1.38,
    double letterSpacing = 0.35,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    // Deterministic per Phase 8: keyed on the occurrence's own `revealId`
    // (falling back to its always-present `id` only for pre-revealId
    // legacy Kept records) -- never on a persisted "chosen prompt" field,
    // and never re-derived from anything that can change across a save.
    _prompt = reflectionPromptFor(widget.item.revealId ?? widget.item.id);
    _lastPersistedText = widget.item.reflection?.trim();
    _controller = TextEditingController(text: widget.item.reflection)
      ..addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_flushPendingSave());
    }
  }

  void _handleTextChanged() {
    // Only for the character counter below the field, which reads
    // `_controller.text` directly in `build()` -- the hint text itself
    // already hides/shows on its own the moment the field stops being
    // empty, with no state of this widget's own involved.
    if (mounted) setState(() {});

    _editRevision += 1;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.autosaveDebounce, () {
      _debounceTimer = null;
      unawaited(_persist());
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF111111),
          content: Text(message, style: _style(17)),
        ),
      );
  }

  /// Cancels any pending debounce and waits for whatever save that pending
  /// (or already in-flight) text change ultimately performs. Called before
  /// this screen is actually allowed to pop, and on the app being
  /// backgrounded, so leaving quickly right after typing never drops the
  /// latest text.
  ///
  /// Returns `true` once the current text is durably persisted (or there
  /// was genuinely nothing new to persist); returns `false` only when a
  /// real, exhausted-retry local-write failure occurred -- see
  /// [_handlePopAttempt], the one caller that acts on this: it must never
  /// let the pop proceed on `false`, since that would silently discard
  /// text the user can no longer recover.
  ///
  /// Real-device repair (Phase 8 follow-up): unlike an ordinary
  /// typing-triggered autosave (where a failure can safely wait for the
  /// user's next keystroke to retry -- they are still on the screen), a
  /// flush has no "next keystroke" to fall back on: the user is actively
  /// leaving. A single transient local-write failure here (momentary disk/
  /// lock contention on a real device -- something no in-memory test double
  /// ever reproduces) must not silently let [_handlePopAttempt] pop the
  /// screen as if nothing needed saving, so this path alone retries before
  /// giving up.
  Future<bool> _flushPendingSave() {
    keptDiagnostic('reflection-screen: flush-begin');
    _debounceTimer?.cancel();
    _debounceTimer = null;
    return _persist(retryOnFailure: true);
  }

  /// The one local-first autosave entry point. Local persistence (via
  /// [SavedReflectionsService.saveReflection], which writes Kept storage
  /// before it ever touches sync state) always happens before the debounce
  /// that gates the *next* attempt -- this method itself never runs on a
  /// timer shorter than [_handleTextChanged]'s own debounce, and
  /// [_flushPendingSave] always cancels that debounce first so a flush
  /// never waits on it. A save already in flight is joined, never
  /// duplicated: a text change that arrives while one is running is folded
  /// into that same drain loop's next pass, so only the latest text is
  /// ever attempted next -- never a queue of stale intermediate values, and
  /// never a mutation per keystroke.
  ///
  /// Root-cause repair (false-success / broken in-flight Future ownership):
  /// this method's own returned `bool` now has one precise meaning --
  /// "every edit up to the revision captured *at this call* is durably
  /// committed" -- computed from [_persistedRevision] *after* the relevant
  /// drain activity settles, never merely "some Future resolved." The
  /// previous version returned [_runPersistLoop]'s own `Future<bool>`
  /// directly and stored that exact object in [_inFlightPersist] one
  /// statement later; when the loop's very first check found nothing to
  /// persist (no real `await` reached), its `finally` block -- which is
  /// ordinary synchronous Dart control flow, unaffected by `async` -- had
  /// already cleared [_inFlightPersist] back to `null` *before* this
  /// method's own next line unconditionally overwrote it right back to
  /// that same, already-finished Future. From that point on
  /// [_inFlightPersist] was permanently non-null for the rest of this
  /// screen's lifetime: every later call took the "join" branch and
  /// resolved instantly against that stale, already-completed Future --
  /// [_attemptPersist] was never invoked again, no matter how much further
  /// text the user typed. [_inFlightPersist] is now `Future<void>` (a pure
  /// "is a drain active" marker) and is cleared *exclusively* via the
  /// `.whenComplete()` callback attached below, from *outside*
  /// [_runPersistLoop] -- `Future` callbacks are never invoked
  /// synchronously in Dart, so that clear can only ever run on a later
  /// microtask, strictly after this method's own `_inFlightPersist = run;`
  /// assignment has already completed. The stale-overwrite race is
  /// therefore structurally impossible, not merely less likely.
  Future<bool> _persist({bool retryOnFailure = false}) {
    final requestedRevision = _editRevision;
    final existing = _inFlightPersist;
    if (existing != null) {
      _persistPending = true;
      return existing.then((_) => _persistedRevision >= requestedRevision);
    }

    late final Future<void> run;
    run = _runPersistLoop(retryOnFailure: retryOnFailure).whenComplete(() {
      // Race-safe by construction (see this method's own doc comment): a
      // `Future` callback is never invoked synchronously, so this can only
      // run after `_inFlightPersist = run;` below has already executed.
      // The `identical` check is defense in depth, not the load-bearing
      // guarantee itself -- it protects against `_inFlightPersist` having
      // since moved on to a genuinely newer run.
      if (identical(_inFlightPersist, run)) {
        _inFlightPersist = null;
      }
    });
    _inFlightPersist = run;
    return run.then((_) => _persistedRevision >= requestedRevision);
  }

  static const int _maxPersistAttempts = 3;
  static const Duration _persistRetryDelay = Duration(milliseconds: 120);

  /// Drains every pending edit revision through authoritative local
  /// persistence -- not "one attempt," but "keep attempting, with the
  /// freshest text each time, until nothing new remains." Advances
  /// [_persistedRevision] itself, exactly once per revision it personally
  /// confirms is either genuinely unchanged (nothing to persist) or freshly
  /// durably written -- never on a failed attempt, so a caller waiting on a
  /// revision that only ever failed correctly computes failure (see
  /// [_persist]).
  Future<void> _runPersistLoop({required bool retryOnFailure}) async {
    while (true) {
      _persistPending = false;
      final revisionBeingAttempted = _editRevision;
      final text = _controller.text;
      final trimmed = text.trim();
      if (trimmed.isNotEmpty && trimmed != _lastPersistedText) {
        final succeeded = await _attemptPersist(
          text: text,
          trimmed: trimmed,
          retryOnFailure: retryOnFailure,
        );
        if (succeeded) {
          _persistedRevision = _persistedRevision > revisionBeingAttempted
              ? _persistedRevision
              : revisionBeingAttempted;
        }
      } else {
        // Nothing new relative to `_lastPersistedText` -- the text as of
        // this exact revision is already durably reflected (or was always
        // empty), so this revision counts as caught up too.
        _persistedRevision = _persistedRevision > revisionBeingAttempted
            ? _persistedRevision
            : revisionBeingAttempted;
      }
      if (!_persistPending) return;
    }
  }

  /// Attempts to persist [text]. When [retryOnFailure] is `false` (an
  /// ordinary typing-triggered autosave), behavior is exactly as before:
  /// one attempt, and a thrown failure surfaces its message immediately --
  /// the user is still on the screen and their next keystroke naturally
  /// retries. When `true` (a pop/backgrounding-triggered flush), a thrown
  /// failure is retried up to [_maxPersistAttempts] times first. Neither
  /// path ever retries a `reflectionLimitReached` rejection -- a permanent
  /// business-rule outcome no retry can change, and that outcome counts as
  /// handled (returns `true`): the text was deliberately not saved by
  /// design, not lost to a write failure.
  ///
  /// Returns `true` on success (including the limit-reached no-op above);
  /// returns `false` only once every attempt has genuinely failed.
  Future<bool> _attemptPersist({
    required String text,
    required String trimmed,
    required bool retryOnFailure,
  }) async {
    final attempts = retryOnFailure ? _maxPersistAttempts : 1;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      keptDiagnostic(
        'reflection-screen: local-write-begin attempt=$attempt/$attempts',
      );
      try {
        final result = await _service.saveReflection(
          itemId: widget.item.id,
          reflection: text,
          isKeeper: _isKeeper,
        );
        if (result.reflectionLimitReached) {
          keptDiagnostic(
            'reflection-screen: local-write-limit-reached attempt=$attempt',
          );
          _showMessage('Keeper unlocks unlimited reflections.');
        } else {
          keptDiagnostic(
            'reflection-screen: local-write-success attempt=$attempt',
          );
          _lastPersistedText = trimmed;
        }
        return true;
      } catch (error) {
        keptDiagnostic(
          'reflection-screen: local-write-failed attempt=$attempt/$attempts '
          'errorType=${error.runtimeType}',
        );
        if (attempt == attempts) {
          keptDiagnostic('reflection-screen: local-write-exhausted');
          if (mounted) {
            _showMessage(
              'Reflection could not be saved. It will try again as you '
              'keep writing.',
            );
          }
          return false;
        }
        // A brief, imperceptible pause before retrying a genuinely
        // transient failure -- never a visible loading state, and short
        // enough that even the worst case (every attempt failing) stays
        // well under a second before the flush this backs gives up.
        await Future<void>.delayed(_persistRetryDelay);
      }
    }
    return false;
  }

  // Approved Ritual direction: the decision to delete is a full-field
  // takeover in the ritual voice, on the horizon, centred -- never a
  // default system alert. Cancel/Delete meaning, the underlying deletion
  // call, and the persisted wisdom being kept are all unchanged from the
  // prior AlertDialog implementation; only the presentation is replaced.
  void _delete() {
    if (_deleteInProgress || !widget.item.hasReflection) return;
    setState(() {
      _confirmingDelete = true;
    });
  }

  void _cancelDelete() {
    if (!mounted) return;
    setState(() {
      _confirmingDelete = false;
    });
  }

  Future<void> _confirmDelete() async {
    if (_deleteInProgress || !mounted) return;

    _debounceTimer?.cancel();
    _debounceTimer = null;
    setState(() {
      _deleteInProgress = true;
    });

    try {
      await _service.deleteReflection(itemId: widget.item.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _deleteInProgress = false;
        _confirmingDelete = false;
      });
      _showMessage('Reflection could not be deleted. Please try again.');
    }
  }

  Widget _deleteDecisionLabel(
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
                  fontWeight: FontWeight.w300,
                  fontFamily: 'CormorantGaramond',
                  letterSpacing: 3.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _deleteDecisionOverlay() {
    if (!_confirmingDelete) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_confirmingDelete,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _confirmingDelete ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('reflection-delete-decision'),
            color: const Color(0xFF040404).withValues(alpha: 0.94),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Delete Reflection?',
                  textAlign: TextAlign.center,
                  style: _style(28, height: 1.1),
                ),
                const SizedBox(height: 16),
                Text(
                  'The reflection will be removed from this kept wisdom.',
                  textAlign: TextAlign.center,
                  style: _style(
                    15,
                    color: const Color(0xB3FFFFFF),
                    height: 1.45,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _deleteDecisionLabel(
                      'CANCEL',
                      onTap: _deleteInProgress ? null : _cancelDelete,
                      color: const Color(0xB3FFFFFF),
                    ),
                    const SizedBox(width: 56),
                    _deleteDecisionLabel(
                      'DELETE',
                      onTap: _deleteInProgress
                          ? null
                          : () => unawaited(_confirmDelete()),
                      color: const Color(0xFFF4F0E8),
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

  /// [PopScope] below deliberately keeps `canPop` `false` forever -- never
  /// flipped -- so it only ever needs to veto the automatic system/gesture
  /// pop while a flush might still be pending. Calling [Navigator.pop]
  /// directly here (never [Navigator.maybePop]) bypasses that veto
  /// unconditionally once the flush has actually finished, with no
  /// setState/rebuild round-trip (and its timing risk) required in between.
  ///
  /// Root-cause repair: a flush that genuinely, persistently fails (every
  /// retry exhausted -- a real on-device disk/file-protection failure, not
  /// a transient blip) must never let the pop through. Popping anyway would
  /// silently discard text the user can no longer recover, directly
  /// contradicting the already-shown "It will try again as you keep
  /// writing." message from [_attemptPersist]. Staying put keeps that
  /// promise true: the text remains in the field, and the very next
  /// keystroke (or another back attempt) is a fresh, real retry.
  Future<void> _handlePopAttempt() async {
    final flushed = await _flushPendingSave();
    if (!mounted) return;
    if (!flushed) {
      keptDiagnostic('reflection-screen: pop-blocked');
      return;
    }
    keptDiagnostic('reflection-screen: pop-allowed');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final characterCount = _controller.text.characters.length;
    const counterThreshold = 220;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        keptDiagnostic('reflection-screen: pop-requested');
        unawaited(_handlePopAttempt());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF040404),
        appBar: AppBar(
          backgroundColor: const Color(0xFF040404),
          foregroundColor: const Color(0xFFF4F0E8),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          leading: Navigator.canPop(context) ? const EastBackButton() : null,
          title: Text('Reflection', style: _style(24)),
          actions: [
            if (widget.item.hasReflection)
              Semantics(
                button: true,
                enabled: !_deleteInProgress,
                label: 'Delete reflection',
                child: ExcludeSemantics(
                  child: TextButton(
                    onPressed: _deleteInProgress ? null : _delete,
                    child: Text('Delete', style: _style(16)),
                  ),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              top: false,
              child: IgnorePointer(
                ignoring: _confirmingDelete,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    16,
                    24,
                    28 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.text,
                        key: const ValueKey('reflection-associated-wisdom'),
                        style: _style(24, height: 1.46),
                      ),
                      const SizedBox(height: 42),
                      TextField(
                        key: const ValueKey('reflection-writing-area'),
                        controller: _controller,
                        enabled: !_deleteInProgress,
                        autofocus: false,
                        keyboardType: TextInputType.multiline,
                        minLines: 7,
                        maxLines: null,
                        maxLength:
                            SavedReflectionsService.maximumReflectionLength,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            SavedReflectionsService.maximumReflectionLength,
                          ),
                        ],
                        style: _style(20, height: 1.45),
                        cursorColor: const Color(0xFFF4F0E8),
                        decoration: InputDecoration(
                          hintText: _prompt,
                          hintStyle: _style(
                            20,
                            color: const Color(0x66FFFFFF),
                            height: 1.45,
                          ),
                          counter: characterCount >= counterThreshold
                              ? Text(
                                  '$characterCount/'
                                  '${SavedReflectionsService.maximumReflectionLength}',
                                  style: _style(
                                    13,
                                    color: const Color(0x91FFFFFF),
                                  ),
                                )
                              : const SizedBox.shrink(),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: eastMutedTextColor,
                              width: 0.5,
                            ),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: eastMutedTextColor,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _deleteDecisionOverlay(),
          ],
        ),
      ),
    );
  }
}
