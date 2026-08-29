import 'package:flutter/services.dart';

import '../controllers/appearance_preference_controller.dart';

class KeeperRitualWidgetCandidate {
  const KeeperRitualWidgetCandidate({
    required this.candidateId,
    required this.canonicalText,
    required this.displayText,
    required this.wisdomId,
    required this.preparedAt,
    required this.activationAt,
  });

  final String candidateId;
  final String canonicalText;
  final String displayText;
  final String wisdomId;
  final DateTime preparedAt;
  final DateTime activationAt;

  static KeeperRitualWidgetCandidate? decode(Object? value) {
    final map = _stringKeyedMap(value);
    if (map == null) return null;
    final candidateId = map['candidateId'];
    final canonicalText = map['canonicalText'];
    final displayText = map['displayText'];
    final wisdomId = map['wisdomId'];
    final preparedAt = _dateFromMillis(map['preparedAtMillis']);
    final activationAt = _dateFromMillis(map['activationAtMillis']);
    if (candidateId is! String ||
        canonicalText is! String ||
        displayText is! String ||
        wisdomId is! String ||
        preparedAt == null ||
        activationAt == null) {
      return null;
    }
    return KeeperRitualWidgetCandidate(
      candidateId: candidateId,
      canonicalText: canonicalText,
      displayText: displayText,
      wisdomId: wisdomId,
      preparedAt: preparedAt,
      activationAt: activationAt,
    );
  }
}

class KeeperRitualWidgetReveal {
  const KeeperRitualWidgetReveal({
    required this.candidateId,
    required this.canonicalText,
    required this.displayText,
    required this.wisdomId,
    required this.revealedAt,
    required this.unlockAt,
    required this.needsAppCommit,
    this.revealId,
  });

  final String candidateId;
  final String canonicalText;
  final String displayText;
  final String wisdomId;
  final DateTime revealedAt;
  final DateTime unlockAt;
  final bool needsAppCommit;
  final String? revealId;

  static KeeperRitualWidgetReveal? decode(Object? value) {
    final map = _stringKeyedMap(value);
    if (map == null) return null;
    final candidateId = map['candidateId'];
    final canonicalText = map['canonicalText'];
    final displayText = map['displayText'];
    final wisdomId = map['wisdomId'];
    final revealedAt = _dateFromMillis(map['revealedAtMillis']);
    final unlockAt = _dateFromMillis(map['unlockAtMillis']);
    final needsAppCommit = map['needsAppCommit'];
    final revealId = map['revealId'];
    if (candidateId is! String ||
        canonicalText is! String ||
        displayText is! String ||
        wisdomId is! String ||
        revealedAt == null ||
        unlockAt == null ||
        needsAppCommit is! bool ||
        (revealId != null && revealId is! String)) {
      return null;
    }
    return KeeperRitualWidgetReveal(
      candidateId: candidateId,
      canonicalText: canonicalText,
      displayText: displayText,
      wisdomId: wisdomId,
      revealedAt: revealedAt,
      unlockAt: unlockAt,
      needsAppCommit: needsAppCommit,
      revealId: revealId as String?,
    );
  }
}

class KeeperRitualWidgetSnapshot {
  const KeeperRitualWidgetSnapshot({
    required this.isKeeper,
    required this.state,
    this.candidate,
    this.nextCandidate,
    this.reveal,
  });

  final bool isKeeper;
  final String state;
  final KeeperRitualWidgetCandidate? candidate;
  final KeeperRitualWidgetCandidate? nextCandidate;
  final KeeperRitualWidgetReveal? reveal;

  static KeeperRitualWidgetSnapshot? decode(Object? value) {
    final map = _stringKeyedMap(value);
    if (map == null) return null;
    final isKeeper = map['isKeeper'];
    final state = map['state'];
    if (isKeeper is! bool || state is! String) return null;
    return KeeperRitualWidgetSnapshot(
      isKeeper: isKeeper,
      state: state,
      candidate: KeeperRitualWidgetCandidate.decode(map['candidate']),
      nextCandidate: KeeperRitualWidgetCandidate.decode(map['nextCandidate']),
      reveal: KeeperRitualWidgetReveal.decode(map['reveal']),
    );
  }
}

/// Failure-contained transport for the separate Keeper ritual widget.
///
/// It performs no selection and owns no daily-access state. The app-side
/// coordinator supplies canonical candidates and reconciles provisional
/// widget reveals into the existing daily-access repository.
class KeeperRitualWidgetService {
  KeeperRitualWidgetService({MethodChannel? methodChannel})
      : _methodChannel = methodChannel ?? const MethodChannel(channelName);

  static const channelName = 'com.dogukan.dailywisdom/widget_snapshot';
  static const _readSnapshot = 'readKeeperRitualSnapshot';
  static const _setEntitlement = 'setKeeperEntitlement';
  static const _publishPrepared = 'publishKeeperPrepared';
  static const _publishActive = 'publishKeeperActive';

  final MethodChannel _methodChannel;

  Future<KeeperRitualWidgetSnapshot?> readSnapshot() async {
    try {
      return KeeperRitualWidgetSnapshot.decode(
        await _methodChannel.invokeMethod<Object?>(_readSnapshot),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> setKeeperEntitlement(bool isKeeper) => _invoke(
        _setEntitlement,
        <String, Object?>{'isKeeper': isKeeper},
      );

  Future<bool> publishPrepared({
    required KeeperRitualWidgetCandidate candidate,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) =>
      _invoke(_publishPrepared, <String, Object?>{
        'candidateId': candidate.candidateId,
        'canonicalText': candidate.canonicalText,
        'displayText': candidate.displayText,
        'wisdomId': candidate.wisdomId,
        'preparedAtMillis': candidate.preparedAt.toUtc().millisecondsSinceEpoch,
        'activationAtMillis':
            candidate.activationAt.toUtc().millisecondsSinceEpoch,
        'appearanceMode': _encodeAppearance(appearanceMode),
        'localeOverrideTag': localeOverrideTag,
      });

  Future<bool> publishActive({
    required KeeperRitualWidgetReveal reveal,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) =>
      _invoke(_publishActive, <String, Object?>{
        'candidateId': reveal.candidateId,
        'canonicalText': reveal.canonicalText,
        'displayText': reveal.displayText,
        'wisdomId': reveal.wisdomId,
        'revealedAtMillis': reveal.revealedAt.toUtc().millisecondsSinceEpoch,
        'unlockAtMillis': reveal.unlockAt.toUtc().millisecondsSinceEpoch,
        'revealId': reveal.revealId,
        'appearanceMode': _encodeAppearance(appearanceMode),
        'localeOverrideTag': localeOverrideTag,
      });

  Future<bool> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      await _methodChannel.invokeMethod<void>(method, arguments);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _encodeAppearance(EastAppearanceMode mode) => switch (mode) {
        EastAppearanceMode.system => 'system',
        EastAppearanceMode.light => 'light',
        EastAppearanceMode.dark => 'dark',
      };
}

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

DateTime? _dateFromMillis(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(value.round(), isUtc: true);
  } catch (_) {
    return null;
  }
}
