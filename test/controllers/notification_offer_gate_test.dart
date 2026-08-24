import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/notification_offer_gate.dart';

void main() {
  testWidgets('busy stays continuous from schedule through async completion',
      (tester) async {
    final completion = Completer<void>();
    final gate = NotificationOfferGate();

    expect(
      gate.schedule(
        delay: const Duration(milliseconds: 10),
        runOffer: () => completion.future,
      ),
      isTrue,
    );
    expect(gate.isBusy, isTrue);
    expect(gate.isShowing, isFalse);

    await tester.pump(const Duration(milliseconds: 10));
    expect(gate.isBusy, isTrue);
    expect(gate.isShowing, isTrue);

    completion.complete();
    await tester.pump();
    expect(gate.isBusy, isFalse);
    expect(gate.isShowing, isFalse);
    gate.dispose();
  });

  testWidgets('a second schedule is rejected while delayed or showing',
      (tester) async {
    final completion = Completer<void>();
    final gate = NotificationOfferGate();

    expect(
      gate.schedule(
        delay: const Duration(milliseconds: 1),
        runOffer: () => completion.future,
      ),
      isTrue,
    );
    expect(
      gate.schedule(delay: Duration.zero, runOffer: () async {}),
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(gate.isShowing, isTrue);
    expect(
      gate.schedule(delay: Duration.zero, runOffer: () async {}),
      isFalse,
    );

    completion.complete();
    await tester.pump();
    gate.dispose();
  });

  testWidgets('completion after an exception still releases the gate',
      (tester) async {
    final gate = NotificationOfferGate();
    gate.schedule(
      delay: const Duration(milliseconds: 1),
      runOffer: () => Future<void>.error(StateError('offer')),
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(gate.isBusy, isFalse);
    expect(gate.isShowing, isFalse);
    gate.dispose();
  });

  testWidgets('dispose cancels a delayed offer permanently', (tester) async {
    var calls = 0;
    final gate = NotificationOfferGate();
    gate.schedule(
      delay: const Duration(milliseconds: 10),
      runOffer: () async => calls++,
    );

    gate.dispose();
    await tester.pump(const Duration(milliseconds: 20));

    expect(calls, 0);
    expect(gate.isBusy, isFalse);
    expect(
      gate.schedule(delay: Duration.zero, runOffer: () async => calls++),
      isFalse,
    );
  });
}
