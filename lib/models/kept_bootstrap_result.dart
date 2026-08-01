/// Outcome of attempting to make the protected Kept storage layer usable at
/// launch.
///
/// Deliberately tiny and narrow: this type carries no exception object, no
/// stack trace, no wisdom or reflection text, and no raw file path — only a
/// stable, content-safe [KeptBootstrapResult.errorCode] when unavailable.
/// Phase 3D-B creates and tests this type only; it is not yet constructed
/// by, or wired into, `app_services.dart` or `main.dart`.
enum KeptBootstrapStatus { ready, unavailable }

class KeptBootstrapResult {
  const KeptBootstrapResult.ready()
      : status = KeptBootstrapStatus.ready,
        errorCode = null;

  KeptBootstrapResult.unavailable(String errorCode)
      : status = KeptBootstrapStatus.unavailable,
        errorCode = _requireNonBlank(errorCode);

  final KeptBootstrapStatus status;

  /// A stable, content-safe diagnostic code (for example
  /// `'protected-store-load-failed'`). Always non-null and non-blank when
  /// [status] is [KeptBootstrapStatus.unavailable]; always `null` when
  /// [status] is [KeptBootstrapStatus.ready]. Never wisdom text, reflection
  /// text, a raw file path, or an exception's `toString()`/stack trace.
  final String? errorCode;

  bool get isReady => status == KeptBootstrapStatus.ready;
  bool get isUnavailable => status == KeptBootstrapStatus.unavailable;

  static String _requireNonBlank(String errorCode) {
    if (errorCode.trim().isEmpty) {
      throw ArgumentError.value(
        errorCode,
        'errorCode',
        'KeptBootstrapResult.unavailable requires a non-blank errorCode.',
      );
    }
    return errorCode;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptBootstrapResult &&
        other.status == status &&
        other.errorCode == errorCode;
  }

  @override
  int get hashCode => Object.hash(status, errorCode);

  @override
  String toString() => switch (status) {
        KeptBootstrapStatus.ready => 'KeptBootstrapResult.ready()',
        KeptBootstrapStatus.unavailable =>
          'KeptBootstrapResult.unavailable($errorCode)',
      };
}
