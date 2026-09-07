import 'package:flutter/services.dart';

import '../data/wisdoms.dart';
import '../models/daily_wisdom_record.dart';

enum DailyRitualAuthorityFailure {
  iCloudRequired,
  connectionRequired,
  unavailable
}

class DailyRitualAuthorityException implements Exception {
  const DailyRitualAuthorityException(this.reason);
  final DailyRitualAuthorityFailure reason;
}

/// A server-authorized occurrence. The public catalog resolves its text on
/// this device; questions, Kept entries and personal writing never cross here.
class AuthorizedDailyRitual {
  const AuthorizedDailyRitual({required this.record, required this.created});
  final DailyWisdomRecord record;
  final bool created;

  static AuthorizedDailyRitual decode(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid daily authorization');
    }
    final wisdomId = value['wisdomId'];
    final entries = wisdoms.where((entry) => entry['id'] == wisdomId);
    final scope = value['accountScope'];
    if (entries.length != 1 ||
        scope is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        value['created'] is! bool) {
      throw const FormatException('Invalid daily authorization');
    }
    final record = DailyWisdomRecord.decodeMap({
      'text': entries.single['text'],
      'wisdomId': wisdomId,
      'revealId': value['revealId'],
      'revealedAtMs': value['revealedAtMs'],
      'unlockAtMs': value['unlockAtMs'],
      'authorityAccountScope': scope,
    });
    if (record.revealId == null) {
      throw const FormatException('Missing authorized occurrence');
    }
    return AuthorizedDailyRitual(
        record: record, created: value['created'] as bool);
  }
}

abstract interface class DailyRitualAuthority {
  /// This is the only way to authorize a new occurrence. It requires an
  /// account and network; an offline cache must never satisfy this operation.
  Future<AuthorizedDailyRitual> claim(
      {required String wisdomId, DailyWisdomRecord? legacyRecord});

  /// Reading a previously authorized occurrence remains available offline.
  Future<AuthorizedDailyRitual?> readCached();

  /// Refreshes the shared occurrence without consuming a new daily right.
  Future<AuthorizedDailyRitual?> refresh({DailyWisdomRecord? legacyRecord});
}

class MethodChannelDailyRitualAuthority implements DailyRitualAuthority {
  const MethodChannelDailyRitualAuthority(
      {this.channel = const MethodChannel(channelName)});
  static const channelName = 'com.dogukan.dailywisdom/daily_ritual';
  final MethodChannel channel;

  @override
  Future<AuthorizedDailyRitual> claim(
      {required String wisdomId, DailyWisdomRecord? legacyRecord}) async {
    final result = await _invoke('claim', {
      'wisdomId': wisdomId,
      ..._legacyArguments(legacyRecord),
    });
    if (result == null) {
      throw const DailyRitualAuthorityException(
          DailyRitualAuthorityFailure.unavailable);
    }
    return result;
  }

  @override
  Future<AuthorizedDailyRitual?> readCached() => _invoke('readCached');

  @override
  Future<AuthorizedDailyRitual?> refresh({DailyWisdomRecord? legacyRecord}) =>
      _invoke('refresh', _legacyArguments(legacyRecord));

  Map<String, Object?> _legacyArguments(DailyWisdomRecord? record) => {
        if (record != null &&
            record.authorityAccountScope == null &&
            record.revealId != null &&
            record.wisdomId != null)
          'legacyRecord': {
            'wisdomId': record.wisdomId,
            'revealId': record.revealId,
            'revealedAtMs': record.revealedAt.millisecondsSinceEpoch,
            'unlockAtMs': record.unlockAt.millisecondsSinceEpoch,
          },
      };

  Future<AuthorizedDailyRitual?> _invoke(String method,
      [Map<String, Object?>? arguments]) async {
    try {
      final result = await channel.invokeMethod<Object?>(method, arguments);
      return result == null ? null : AuthorizedDailyRitual.decode(result);
    } on PlatformException catch (error) {
      throw DailyRitualAuthorityException(switch (error.code) {
        'icloud_required' => DailyRitualAuthorityFailure.iCloudRequired,
        'connection_required' => DailyRitualAuthorityFailure.connectionRequired,
        _ => DailyRitualAuthorityFailure.unavailable,
      });
    } catch (_) {
      throw const DailyRitualAuthorityException(
          DailyRitualAuthorityFailure.unavailable);
    }
  }
}
