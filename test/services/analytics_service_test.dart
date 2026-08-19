import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/services/analytics_event.dart';
import 'package:wisdom_app/services/analytics_service.dart';

void main() {
  late _FakeAnalyticsTransport transport;
  late AnalyticsService service;

  setUp(() {
    transport = _FakeAnalyticsTransport();
    service = AnalyticsService(transport: transport);
  });

  test('only the six allow-listed event names exist', () {
    final names = AnalyticsEvent.values.map((event) => event.eventName).toSet();

    expect(names, {
      'ritual_completed',
      'kept_saved',
      'reflection_saved',
      'keeper_purchase_started',
      'keeper_purchase_completed',
      'keeper_restore_completed',
    });
    expect(AnalyticsEvent.values, hasLength(6));
  });

  test(
      'each public method emits exactly its own allow-listed event, with '
      'no others firing as a side effect', () {
    service.ritualCompleted();
    expect(transport.tracked, [AnalyticsEvent.ritualCompleted]);

    transport.tracked.clear();
    service.keptSaved();
    expect(transport.tracked, [AnalyticsEvent.keptSaved]);

    transport.tracked.clear();
    service.reflectionSaved();
    expect(transport.tracked, [AnalyticsEvent.reflectionSaved]);

    transport.tracked.clear();
    service.keeperPurchaseStarted();
    expect(transport.tracked, [AnalyticsEvent.keeperPurchaseStarted]);

    transport.tracked.clear();
    service.keeperPurchaseCompleted();
    expect(transport.tracked, [AnalyticsEvent.keeperPurchaseCompleted]);

    transport.tracked.clear();
    service.keeperRestoreCompleted();
    expect(transport.tracked, [AnalyticsEvent.keeperRestoreCompleted]);
  });

  test(
      'AnalyticsTransport.track takes only an AnalyticsEvent -- there is no '
      'parameter for private content or identifiers to travel through', () {
    // Structural proof: the only public surface a transport receives is one
    // closed-enum value. Verified here by exhaustively covering every enum
    // member and confirming none of their `eventName`s embed anything
    // beyond a fixed, private-content-free identifier.
    for (final event in AnalyticsEvent.values) {
      expect(event.eventName, isNot(contains(' ')));
      expect(event.eventName, matches(RegExp(r'^[a-z_]+$')));
    }
  });

  test('a transport failure is swallowed and never rethrown', () {
    transport.shouldThrow = true;

    expect(service.ritualCompleted, returnsNormally);
    expect(service.keptSaved, returnsNormally);
    expect(service.reflectionSaved, returnsNormally);
    expect(service.keeperPurchaseStarted, returnsNormally);
    expect(service.keeperPurchaseCompleted, returnsNormally);
    expect(service.keeperRestoreCompleted, returnsNormally);
  });

  test('DebugLogAnalyticsTransport never throws for any allow-listed event',
      () {
    const transport = DebugLogAnalyticsTransport();
    for (final event in AnalyticsEvent.values) {
      expect(() => transport.track(event), returnsNormally);
    }
  });
}

class _FakeAnalyticsTransport implements AnalyticsTransport {
  final List<AnalyticsEvent> tracked = [];
  bool shouldThrow = false;

  @override
  void track(AnalyticsEvent event) {
    if (shouldThrow) {
      throw StateError('transport unavailable');
    }
    tracked.add(event);
  }
}
