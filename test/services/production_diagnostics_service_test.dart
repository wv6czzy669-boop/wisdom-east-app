import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/services/production_diagnostics_service.dart';
import 'package:wisdom_app/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';

void main() {
  test('every sync outcome maps to one closed content-free signal', () async {
    final transport = _RecordingTransport();
    final service = ProductionDiagnosticsService(transport: transport);

    for (final outcome in SyncRuntimeOutcome.values) {
      service.recordSyncOutcome(outcome);
    }
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.signals,
      <ProductionDiagnosticSignal>[
        ProductionDiagnosticSignal.syncCompleted,
        ProductionDiagnosticSignal.syncRetryableFailure,
        ProductionDiagnosticSignal.syncTerminalFailure,
        ProductionDiagnosticSignal.syncWaitingForICloud,
        ProductionDiagnosticSignal.syncDeletionStateCorrupted,
        ProductionDiagnosticSignal.syncDeletionStateCorrupted,
        ProductionDiagnosticSignal.syncDeletionProgressed,
        ProductionDiagnosticSignal.syncDeletionCompleted,
      ],
    );
  });

  test('transport failure is fully contained', () async {
    final service = ProductionDiagnosticsService(
      transport: _RecordingTransport()..fail = true,
    );

    service.recordSyncOutcome(SyncRuntimeOutcome.terminalFailure);
    await expectLater(Future<void>.delayed(Duration.zero), completes);
  });

  test('signal enum exposes no parameter or user-content surface', () {
    expect(ProductionDiagnosticSignal.values, hasLength(7));
    for (final signal in ProductionDiagnosticSignal.values) {
      expect(signal.name, startsWith('sync'));
    }
  });
}

final class _RecordingTransport implements ProductionDiagnosticsTransport {
  final List<ProductionDiagnosticSignal> signals = [];
  bool fail = false;

  @override
  Future<void> record(ProductionDiagnosticSignal signal) async {
    if (fail) throw StateError('transport unavailable');
    signals.add(signal);
  }
}
