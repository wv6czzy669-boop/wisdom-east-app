import 'dart:async';

import 'package:flutter/services.dart';

import '../sync_runtime/cloud_kit_sync_runtime_coordinator.dart';

/// Closed, parameter-free production-health signals. No content, identity,
/// timestamp, account value, record name, or exception can be attached.
enum ProductionDiagnosticSignal {
  syncCompleted,
  syncRetryableFailure,
  syncTerminalFailure,
  syncWaitingForICloud,
  syncDeletionProgressed,
  syncDeletionCompleted,
  syncDeletionStateCorrupted,
}

abstract interface class ProductionDiagnosticsTransport {
  Future<void> record(ProductionDiagnosticSignal signal);
}

final class MethodChannelProductionDiagnosticsTransport
    implements ProductionDiagnosticsTransport {
  const MethodChannelProductionDiagnosticsTransport();

  static const String channelName =
      'com.dogukan.dailywisdom/production_diagnostics';
  static const String methodName = 'recordSignal';
  static const MethodChannel _channel = MethodChannel(channelName);

  @override
  Future<void> record(ProductionDiagnosticSignal signal) async {
    await _channel.invokeMethod<void>(methodName, <String, Object?>{
      'signal': signal.name,
    });
  }
}

/// Privacy-first production observability.
///
/// The native side combines these content-free sync outcome counters with
/// MetricKit crash/hang delivery. Every call is fire-and-forget and fully
/// failure-contained, so diagnostics can never alter sync behavior.
final class ProductionDiagnosticsService {
  ProductionDiagnosticsService({ProductionDiagnosticsTransport? transport})
      : _transport =
            transport ?? const MethodChannelProductionDiagnosticsTransport();

  final ProductionDiagnosticsTransport _transport;

  void recordSyncOutcome(SyncRuntimeOutcome outcome) {
    final signal = switch (outcome) {
      SyncRuntimeOutcome.completed => ProductionDiagnosticSignal.syncCompleted,
      SyncRuntimeOutcome.retryableFailure =>
        ProductionDiagnosticSignal.syncRetryableFailure,
      SyncRuntimeOutcome.terminalFailure =>
        ProductionDiagnosticSignal.syncTerminalFailure,
      SyncRuntimeOutcome.waitingForAccountAvailability =>
        ProductionDiagnosticSignal.syncWaitingForICloud,
      SyncRuntimeOutcome.deletionRecoveryProgressed =>
        ProductionDiagnosticSignal.syncDeletionProgressed,
      SyncRuntimeOutcome.deletionCompleted =>
        ProductionDiagnosticSignal.syncDeletionCompleted,
      SyncRuntimeOutcome.deletionPending ||
      SyncRuntimeOutcome.deletionStateCorrupted =>
        ProductionDiagnosticSignal.syncDeletionStateCorrupted,
    };
    unawaited(_transport.record(signal).catchError((_) {}));
  }
}
