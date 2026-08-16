import 'package:flutter/services.dart';

/// EAST. Phase 11 -- the Dart side of the Home Screen widget's snapshot
/// bridge, backed by the native `EastWidgetSnapshotBridge`
/// (`ios/Runner/EastWidgetSnapshotBridge.swift`).
///
/// `DailyWisdomAccessService` remains the sole authority on what wisdom
/// exists and when it unlocks -- this service never selects, generates, or
/// reveals anything. It only ever mirrors an already-committed occurrence's
/// revealed text and unlock/expiry `Date` into the widget's own App Group
/// storage, at the two call sites that matter: a genuinely new, durably
/// committed reveal (`publishRevealed`), and a resume-time reconciliation
/// against the current authoritative status (`publishRevealed`/
/// `publishSilence`).
///
/// Fully failure-contained, mirroring `WisdomNotificationService`: every
/// method swallows its own errors rather than throwing, since a widget-sync
/// failure must never affect the daily-access flow it observes.
class WidgetSnapshotService {
  WidgetSnapshotService({MethodChannel? methodChannel})
      : _methodChannel = methodChannel ?? const MethodChannel(channelName);

  static const String channelName = 'com.dogukan.dailywisdom/widget_snapshot';
  static const String _methodPublishRevealed = 'publishRevealed';
  static const String _methodPublishSilence = 'publishSilence';
  static const String _argText = 'text';
  static const String _argUnlockAtMillis = 'unlockAtMillis';

  final MethodChannel _methodChannel;

  /// Mirrors a genuinely revealed occurrence -- [text] verbatim, [unlockAt]
  /// as the widget's only notion of "when this expires back to silence".
  Future<void> publishRevealed({
    required String text,
    required DateTime unlockAt,
  }) async {
    try {
      await _methodChannel.invokeMethod(_methodPublishRevealed, {
        _argText: text,
        _argUnlockAtMillis: unlockAt.toUtc().millisecondsSinceEpoch,
      });
    } catch (_) {
      // A widget-sync failure must never affect the daily-access flow that
      // triggered it -- this is best-effort mirroring only.
    }
  }

  /// Mirrors "nothing is currently revealed" -- used at resume-time
  /// reconciliation when the authoritative status is ready-to-reveal (no
  /// currently locked occurrence).
  Future<void> publishSilence() async {
    try {
      await _methodChannel.invokeMethod(_methodPublishSilence);
    } catch (_) {
      // Best-effort, matching publishRevealed above.
    }
  }
}
