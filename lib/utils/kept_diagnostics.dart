import 'package:flutter/foundation.dart';

/// Privacy-safe debug logging for Kept storage and sync state transitions.
///
/// Hard rules every call site in this diagnostic pass must follow:
///  * Never log or persist wisdom text, reflection text, a raw legacy
///    `favorites` entry, or the contents of any JSON file. Only stage
///    names, exception *types*, exception *codes*, already-sanitized
///    exception `.message` strings (the project's own store/migration
///    exception types already document their `.message` as safe — never
///    their `.cause`, and never any error's bare `.toString()`, which for
///    something like a `FormatException` thrown by `jsonDecode` on corrupt
///    input can echo a fragment of the actual source text being parsed),
///    file paths, and file-existence booleans are ever passed in here.
///  * Logging is a no-op outside [kDebugMode] — this must never
///    affect Release-build behavior, timing, or persisted application
///    state.
const String keptDiagnosticLogPrefix = 'EAST_KEPT_DIAGNOSTIC';

/// Logs [message] with the stable [keptDiagnosticLogPrefix], only in
/// [kDebugMode]. A complete no-op in Release/profile builds.
void keptDiagnostic(String message) {
  if (!kDebugMode) return;
  debugPrint('$keptDiagnosticLogPrefix $message');
}
