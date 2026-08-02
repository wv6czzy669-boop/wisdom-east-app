/// Build 26 Phase 4B-1: the content-free account-change event emitted by
/// the native bridge's event stream (see
/// `lib/sync_platform/cloud_kit_platform_bridge.dart`'s
/// `accountChangeEvents`). Carries no account or user identity of any
/// kind -- callers must explicitly call `getAccountSnapshot` afterward
/// (design doc §5).
library;

enum CloudKitAccountChangeEventKind {
  accountChanged,
}

final class CloudKitAccountChangeEvent {
  const CloudKitAccountChangeEvent({required this.kind});

  final CloudKitAccountChangeEventKind kind;

  /// Parses a loosely-typed native event payload. Returns `null` for
  /// anything malformed or unrecognized -- never throws. A caller that
  /// receives `null` here simply drops the event; it is never surfaced as
  /// a stream error (see
  /// `lib/sync_platform/method_channel_cloud_kit_platform_bridge.dart`).
  static CloudKitAccountChangeEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final eventValue = raw['event'];
    if (eventValue != 'accountChanged') return null;
    return const CloudKitAccountChangeEvent(
      kind: CloudKitAccountChangeEventKind.accountChanged,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CloudKitAccountChangeEvent && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'CloudKitAccountChangeEvent(${kind.name})';
}
