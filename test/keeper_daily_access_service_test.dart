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
    final second = await service.reveal(selectWisdom: select);
    final third = await service.reveal(selectWisdom: select);
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

    await service.reveal(selectWisdom: select);
    await service.reveal(selectWisdom: select);
    await service.reveal(selectWisdom: select);
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

  test('clock rollback does not reset the Keeper allowance', () async {
    await service.reveal(selectWisdom: () => 'One');
    await service.reveal(selectWisdom: () => 'Two');
    await service.reveal(selectWisdom: () => 'Three');

    now = DateTime(2026, 6, 19, 10);
    final status = await service.status();

    expect(status.revealCount, 3);
    expect(status.canReveal, isFalse);
    expect(status.lastWisdom, 'Three');
  });
}
