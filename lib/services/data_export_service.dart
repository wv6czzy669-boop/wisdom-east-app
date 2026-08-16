import 'package:share_plus/share_plus.dart';

import 'data_export_builder.dart';
import 'journal_owner_service.dart';
import 'saved_reflections_service.dart';

typedef DataExportShareLauncher = Future<ShareResult> Function(
  ShareParams params,
);

/// EAST. — "Export My Data": free, on-device, user-owned data export.
///
/// Orchestrates the read-only path from already-existing local services
/// (`SavedReflectionsService.load()`, `JournalOwnerService.loadName()` --
/// both already the exact read models Kept/Return/Journal use) into
/// [DataExportBuilder]'s two in-memory payloads, then hands them to the
/// native Share Sheet via `share_plus` -- the same package/API
/// `WisdomShareService` already uses for a single file. No CloudKit read,
/// no network call, no analytics event, and nothing here can mutate Kept,
/// Reflection, or sync state -- every dependency this class touches is a
/// plain read.
///
/// Free and Keeper receive byte-for-byte identical behavior: this class
/// never reads `PurchaseService`/entitlement state at all.
///
/// [savedReflectionsServiceProvider] is a *provider*, not the service
/// itself: `app_services.dart`'s own `savedReflectionsService` is a `late
/// final` populated only once `initializeKeptStorage()` completes, and this
/// service (constructed as an eager top-level global alongside it) must
/// never dereference that field before it is actually used -- exactly the
/// same lazy-closure pattern `app_services.dart` already uses for its own
/// `onMutationCommitted` callbacks.
class DataExportService {
  DataExportService({
    required SavedReflectionsService Function() savedReflectionsServiceProvider,
    JournalOwnerService? journalOwnerService,
    DataExportBuilder? builder,
    DateTime Function()? clock,
    DataExportShareLauncher? shareLauncher,
  })  : _savedReflectionsServiceProvider = savedReflectionsServiceProvider,
        _journalOwnerService = journalOwnerService ?? JournalOwnerService(),
        _builder = builder ?? const DataExportBuilder(),
        _clock = clock ?? DateTime.now,
        _shareLauncher = shareLauncher ?? SharePlus.instance.share;

  final SavedReflectionsService Function() _savedReflectionsServiceProvider;
  final JournalOwnerService _journalOwnerService;
  final DataExportBuilder _builder;
  final DateTime Function() _clock;
  final DataExportShareLauncher _shareLauncher;

  /// Builds both export files and presents the native Share Sheet with
  /// both attached. Returns `true` once the share sheet was successfully
  /// invoked (regardless of which destination, if any, the user ultimately
  /// picks -- exactly like `WisdomShareService`, this is not a delivery
  /// receipt). Returns `false` on any failure -- generation or
  /// presentation -- without ever mutating Kept/Reflection/sync state,
  /// which this class never writes to in the first place.
  Future<bool> exportAndShare() async {
    try {
      final items = await _savedReflectionsServiceProvider().load();
      final ownerName = await _journalOwnerService.loadName();

      final document = _builder.build(
        items: items,
        journalOwnerName: ownerName,
        exportedAt: _clock(),
      );

      await _shareLauncher(
        ShareParams(
          files: [
            XFile.fromData(
              document.jsonBytes,
              mimeType: 'application/json',
              name: document.jsonFilename,
            ),
            XFile.fromData(
              document.txtBytes,
              mimeType: 'text/plain',
              name: document.txtFilename,
            ),
          ],
          fileNameOverrides: [document.jsonFilename, document.txtFilename],
          subject: 'EAST. Data Export',
          downloadFallbackEnabled: false,
        ),
      );
      return true;
    } catch (_) {
      // Never logs wisdom/Reflection/owner-name content or exception
      // details -- a failure here is reported to the user only as a
      // single quiet, generic message (see `SettingsScreen`).
      return false;
    }
  }
}
