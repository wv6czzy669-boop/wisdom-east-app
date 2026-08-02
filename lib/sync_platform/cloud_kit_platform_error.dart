import '../sync/sync_error_classification.dart';

/// Build 26 Phase 4B-1: a safe, typed error for the CloudKit platform
/// bridge. Carries only a symbolic [code] -- reusing the exact same
/// vocabulary `lib/sync/sync_error_classification.dart` already defines
/// (Phase 4A), so this layer never maintains a second, independently
/// drifting classification scheme. Never carries a raw native/localized
/// message string: see `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s
/// Phase 4B-1 section, "native exceptions map to safe typed errors without
/// forwarding localized messages".
final class CloudKitPlatformException implements Exception {
  const CloudKitPlatformException(this.code);

  /// A symbolic error code. May be one of the recognized
  /// `lib/sync/sync_error_classification.dart` constants, or an
  /// unrecognized code the native side reported -- [classifySyncErrorCode]
  /// safely defaults any unrecognized code to
  /// [SyncErrorCategory.permanent] (fail closed), so this layer needs no
  /// fallback classification logic of its own.
  final String code;

  /// The handling category for [code], reusing the single existing pure
  /// classifier rather than a second copy.
  SyncErrorCategory get category => classifySyncErrorCode(code);

  /// No native handler was registered for the CloudKit sync channel at all
  /// (`MissingPluginException`) -- distinct from a handler running and
  /// reporting a real failure.
  static const String noNativeHandlerCode = 'nativeHandlerUnavailable';

  /// The native side reported a `PlatformException` with an empty/blank
  /// code, or threw something that was not a recognized channel exception
  /// type at all.
  static const String unrecognizedNativeErrorCode = 'unrecognizedNativeError';

  /// The native side returned a result that did not parse as the expected
  /// model shape (see each model's `tryParse`).
  static const String malformedResultCode = 'malformedNativeResult';

  @override
  String toString() => 'CloudKitPlatformException($code)';

  @override
  bool operator ==(Object other) =>
      other is CloudKitPlatformException && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
