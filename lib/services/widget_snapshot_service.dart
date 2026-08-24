import 'package:flutter/services.dart';

import '../controllers/appearance_preference_controller.dart';

/// EAST. Phase 11, extended in 1.2 Slice 3 -- the Dart side of the Home
/// Screen widget's snapshot bridge, backed by the native
/// `EastWidgetSnapshotBridge` (`ios/Runner/EastWidgetSnapshotBridge.swift`).
///
/// `DailyWisdomAccessService` remains the sole authority on what wisdom
/// exists and when it unlocks -- this service never selects, generates, or
/// reveals anything, and never performs localization or state lookup of its
/// own. It only ever crosses exactly what its caller (`WidgetPresentation
/// SyncCoordinator`) already resolved: the revealed text and unlock/expiry
/// `Date`, plus the caller's already-resolved presentation (appearance mode
/// and an optional explicit locale override tag).
///
/// Fully failure-contained, mirroring `WisdomNotificationService`: every
/// method swallows its own errors rather than throwing, since a widget-sync
/// failure must never affect the daily-access flow that triggered it.
class WidgetSnapshotService {
  WidgetSnapshotService({MethodChannel? methodChannel})
      : _methodChannel = methodChannel ?? const MethodChannel(channelName);

  static const String channelName = 'com.dogukan.dailywisdom/widget_snapshot';
  static const String _methodPublishRevealed = 'publishRevealed';
  static const String _methodPublishSilence = 'publishSilence';
  static const String _argText = 'text';
  static const String _argUnlockAtMillis = 'unlockAtMillis';
  static const String _argAppearanceMode = 'appearanceMode';
  static const String _argLocaleOverrideTag = 'localeOverrideTag';

  final MethodChannel _methodChannel;

  /// Mirrors a genuinely revealed occurrence -- [text] verbatim, [unlockAt]
  /// as the widget's only notion of "when this expires back to silence" --
  /// alongside the caller's already-resolved [appearanceMode] and
  /// [localeOverrideTag]. [localeOverrideTag] is `null` for System Default;
  /// the key is always sent, even when its value is `null`, so the native
  /// side can distinguish "explicitly System Default" from "no presentation
  /// payload at all" (a legacy caller).
  Future<void> publishRevealed({
    required String text,
    required DateTime unlockAt,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    try {
      await _methodChannel.invokeMethod(_methodPublishRevealed, {
        _argText: text,
        _argUnlockAtMillis: unlockAt.toUtc().millisecondsSinceEpoch,
        _argAppearanceMode: _encodeAppearanceMode(appearanceMode),
        _argLocaleOverrideTag: localeOverrideTag,
      });
    } catch (_) {
      // A widget-sync failure must never affect the daily-access flow that
      // triggered it -- this is best-effort mirroring only.
    }
  }

  /// Mirrors "nothing is currently revealed" -- used whenever the
  /// authoritative status is ready-to-reveal (no currently locked
  /// occurrence), alongside the caller's already-resolved [appearanceMode]
  /// and [localeOverrideTag] -- the silence card itself still renders in
  /// the current appearance/language, so both fields cross here too.
  Future<void> publishSilence({
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    try {
      await _methodChannel.invokeMethod(_methodPublishSilence, {
        _argAppearanceMode: _encodeAppearanceMode(appearanceMode),
        _argLocaleOverrideTag: localeOverrideTag,
      });
    } catch (_) {
      // Best-effort, matching publishRevealed above.
    }
  }

  /// The exact three wire values `EastWidgetAppearanceMode(rawValue:)`
  /// (native) recognizes -- see
  /// `ios/EastShared/EastWidgetSnapshotStore.swift`.
  static String _encodeAppearanceMode(EastAppearanceMode mode) {
    switch (mode) {
      case EastAppearanceMode.system:
        return 'system';
      case EastAppearanceMode.light:
        return 'light';
      case EastAppearanceMode.dark:
        return 'dark';
    }
  }
}
