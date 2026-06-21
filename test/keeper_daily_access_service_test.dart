import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/services/keeper_daily_access_service.dart';
import 'package:wisdom_app/services/storage_service.dart';

void main() {
  late DateTime now;
  late KeeperDailyAccessService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 6, 20, 10);
    service = KeeperDailyAccessService(
      storageService: StorageService(),
      clock: () => now,
    );
  });

  test('Keeper receives three wisdoms and then remains locked', () async {
    var selections = 0;
    String select() => 'Keeper wisdom ${++selections}';

    final first = await service.reveal(selectWisdom: select);
    await service.markDisplayed(first.text);
    final second = await service.reveal(selectWisdom: select);
    await service.markDisplayed(second.text);
    final third = await service.reveal(selectWisdom: select);
    await service.markDisplayed(third.text);
    final locked = await service.reveal(selectWisdom: select);

    expect(first.text, 'Keeper wisdom 1');
    expect(first.status.canReveal, isTrue);
    expect(second.text, 'Keeper wisdom 2');
    expect(second.status.canReveal, isTrue);
    expect(third.text, 'Keeper wisdom 3');
    expect(third.status.canReveal, isFalse);
    expect(locked.text, 'Keeper wisdom 3');
    expect(locked.isNew, isFalse);
    expect(selections, 3);
  });

  test('Keeper daily count resets when the local date changes', () async {
    var selections = 0;
    String select() => 'Keeper wisdom ${++selections}';

    for (var index = 0; index < 3; index++) {
      final access = await service.reveal(selectWisdom: select);
      await service.markDisplayed(access.text);
    }
    expect((await service.status()).canReveal, isFalse);

    now = DateTime(2026, 6, 21, 0, 0, 1);
    final resetStatus = await service.status();

    expect(resetStatus.revealCount, 0);
    expect(resetStatus.canReveal, isTrue);
    expect(resetStatus.lastWisdom, 'Keeper wisdom 3');
    expect(resetStatus.resetAt, DateTime(2026, 6, 22));

    final nextDay = await service.reveal(selectWisdom: select);
    expect(nextDay.text, 'Keeper wisdom 4');
    expect(nextDay.status.revealCount, 1);
  });

  test('Keeper state survives service recreation', () async {
    await service.reveal(selectWisdom: () => 'Persisted Keeper wisdom');

    final recreated = KeeperDailyAccessService(
      storageService: StorageService(),
      clock: () => now,
    );
    final status = await recreated.status();

    expect(status.revealCount, 1);
    expect(status.lastWisdom, 'Persisted Keeper wisdom');
    expect(status.canReveal, isTrue);
  });

  test('same-day free wisdom consumes the first Keeper reveal', () async {
    await service.seedFromExistingWisdomIfNeeded(
      text: 'Free wisdom before purchase',
      revealedAt: DateTime(2026, 6, 20, 8),
    );

    final status = await service.status();

    expect(status.revealCount, 1);
    expect(status.lastWisdom, 'Free wisdom before purchase');
    expect(status.canReveal, isTrue);
  });

  test('an older free wisdom does not consume the new local-day allowance',
      () async {
    await service.seedFromExistingWisdomIfNeeded(
      text: 'Yesterday wisdom',
      revealedAt: DateTime(2026, 6, 19, 23),
    );

    final status = await service.status();

    expect(status.revealCount, 0);
    expect(status.lastWisdom, isNull);
  });

  test('concurrent Keeper reveals select and persist only one wisdom',
      () async {
    var selections = 0;
    String select() => 'Concurrent Keeper wisdom ${++selections}';

    final results = await Future.wait([
      service.reveal(selectWisdom: select),
      service.reveal(selectWisdom: select),
    ]);

    expect(selections, 1);
    expect(
      results.map((result) => result.text).toSet(),
      {'Concurrent Keeper wisdom 1'},
    );
    expect((await service.status()).revealCount, 1);
  });

  test(
      'interrupted persisted reveal returns exact wisdom without count increase',
      () async {
    var selections = 0;
    String select() => 'Interrupted Keeper wisdom ${++selections}';

    final selected = await service.reveal(selectWisdom: select);
    expect(selected.status.revealCount, 1);
    expect(selected.status.hasPendingReveal, isTrue);

    final recreated = KeeperDailyAccessService(
      storageService: StorageService(),
      clock: () => now,
    );
    final resumed = await recreated.reveal(selectWisdom: select);

    expect(resumed.text, selected.text);
    expect(resumed.isNew, isFalse);
    expect(resumed.status.revealCount, 1);
    expect(selections, 1);

    await recreated.markDisplayed(resumed.text);
    final afterDisplay = await recreated.status();
    expect(afterDisplay.revealCount, 1);
    expect(afterDisplay.hasPendingReveal, isFalse);

    final next = await recreated.reveal(selectWisdom: select);
    expect(next.text, 'Interrupted Keeper wisdom 2');
    expect(next.status.revealCount, 2);
  });

  test('serialized seed status and reveal cannot reduce the reveal count',
      () async {
    final seed = service.seedFromExistingWisdomIfNeeded(
      text: 'Existing free wisdom',
      revealedAt: now.subtract(const Duration(hours: 1)),
    );
    final reveal = service.reveal(selectWisdom: () => 'Keeper wisdom');
    final status = service.status();

    await seed;
    final access = await reveal;
    final observed = await status;
    final persisted = await service.status();

    expect(access.status.revealCount, 2);
    expect(observed.revealCount, 2);
    expect(persisted.revealCount, 2);
    expect(persisted.lastWisdom, 'Keeper wisdom');
  });

  test('pending wisdom survives local midnight before the new allowance',
      () async {
    now = DateTime(2026, 6, 20, 23, 59, 59);
    final selected = await service.reveal(
      selectWisdom: () => 'Wisdom across midnight',
    );

    now = DateTime(2026, 6, 21, 0, 0, 1);
    final resumed = await service.reveal(
      selectWisdom: () => 'Must not be selected',
    );

    expect(resumed.text, selected.text);
    expect(resumed.isNew, isFalse);
    expect(resumed.status.revealCount, 1);
    expect(resumed.status.hasPendingReveal, isTrue);

    await service.markDisplayed(resumed.text);
    final newDay = await service.status();
    expect(newDay.revealCount, 0);
    expect(newDay.canReveal, isTrue);
    expect(newDay.lastWisdom, resumed.text);
  });

  test('clock rollback does not reset the Keeper allowance', () async {
    for (final text in ['One', 'Two', 'Three']) {
      final access = await service.reveal(selectWisdom: () => text);
      await service.markDisplayed(access.text);
    }

    now = DateTime(2026, 6, 19, 10);
    final status = await service.status();

    expect(status.revealCount, 3);
    expect(status.canReveal, isFalse);
    expect(status.lastWisdom, 'Three');
  });
}
