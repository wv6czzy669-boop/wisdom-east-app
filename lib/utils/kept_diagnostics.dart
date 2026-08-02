import 'package:flutter/foundation.dart';

import '../persistence/storage_preferences_adapter.dart';

/// TEMPORARY Phase 3D-D real-device diagnostic instrumentation.
///
/// Everything in this file exists solely to let one physical-device run
/// conclusively identify which exact stage of Kept storage startup is
/// failing. It is not part of the permanent EAST architecture and should be
/// removed once that stage is identified and the real fix has landed.
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
///  * Everything below is a no-op outside [kDebugMode] — this must never
///    affect Release-build behavior, timing, or persisted application
///    state.
const String keptDiagnosticLogPrefix = 'EAST_KEPT_DIAGNOSTIC';

/// TEMPORARY debug-only SharedPreferences key. Deliberately named so it is
/// unmistakably not part of the protected Kept-state envelope or any
/// production data path — this is a disposable, content-free breadcrumb of
/// the single most recent diagnostic failure, for this diagnostic turn
/// only.
const String keptDiagnosticLastKey = 'east_kept_diagnostic_last_TEMPORARY';

/// Logs [message] with the stable [keptDiagnosticLogPrefix], only in
/// [kDebugMode]. A complete no-op in Release/profile builds.
void keptDiagnostic(String message) {
  if (!kDebugMode) return;
  debugPrint('$keptDiagnosticLogPrefix $message');
}

/// Persists a small, content-free "last diagnostic" breadcrumb — [stage],
/// [errorType], and optionally [errorCode]/[message] — only in
/// [kDebugMode]. Every argument must already be safe to persist in plain
/// text (see the file-level doc comment); this function does no sanitizing
/// of its own.
///
/// Best-effort only: any failure to persist is swallowed so this diagnostic
/// aid can never itself cause (or mask) a real bootstrap/migration failure.
Future<void> persistKeptDiagnosticLast({
  required String stage,
  required String errorType,
  String? errorCode,
  String? message,
  StoragePreferencesAdapter? preferencesAdapter,
}) async {
  if (!kDebugMode) return;
  try {
    final adapter = preferencesAdapter ?? StoragePreferencesAdapter();
    final summary = <String>[
      'stage=$stage',
      'errorType=$errorType',
      if (errorCode != null) 'errorCode=$errorCode',
      if (message != null) 'message=$message',
    ].join(' | ');
    await adapter.setString(keptDiagnosticLastKey, summary);
  } catch (_) {
    // Best-effort only.
  }
}
