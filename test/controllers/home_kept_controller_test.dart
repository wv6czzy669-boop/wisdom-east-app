import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/home_kept_controller.dart';
import 'package:wisdom_app/models/favorite_item.dart';

void main() {
  FavoriteItem item(String id, String revealId) => FavoriteItem(
        id: id,
        revealId: revealId,
        text: 'Wisdom $id',
        date: 'August 24, 2026',
      );

  test('matches the current occurrence by revealId, never by text', () async {
    final first = item('first', 'reveal-1');
    final repeatedText = FavoriteItem(
      id: 'second',
      revealId: 'reveal-2',
      text: first.text,
      date: first.date,
    );
    final controller = HomeKeptController(
      loadItems: () async => [first, repeatedText],
      keepWisdom: (_) async => throw UnimplementedError(),
    );

    expect(await controller.load(), isTrue);
    expect(controller.currentFavorite('reveal-2')?.id, 'second');
    expect(controller.currentFavorite(null), isNull);
    expect(controller.currentFavorite('missing'), isNull);
  });

  test('a failed load preserves the last known projection', () async {
    var fail = false;
    final existing = item('existing', 'reveal-existing');
    final controller = HomeKeptController(
      loadItems: () async {
        if (fail) throw StateError('protected storage unavailable');
        return [existing];
      },
      keepWisdom: (_) async => throw UnimplementedError(),
    );

    expect(await controller.load(), isTrue);
    fail = true;
    expect(await controller.load(), isFalse);
    expect(controller.items, [existing]);
  });

  test('a successful Keep replaces the projection', () async {
    final kept = item('kept', 'reveal-kept');
    late HomeKeepRequest captured;
    final controller = HomeKeptController(
      loadItems: () async => const [],
      keepWisdom: (request) async {
        captured = request;
        return HomeKeptWriteResult(items: [kept], limitReached: false);
      },
    );
    final revealedAt = DateTime.utc(2026, 8, 24);

    final result = await controller.keep(HomeKeepRequest(
      text: 'Stay.',
      date: 'August 24, 2026',
      isKeeper: true,
      revealId: 'reveal-kept',
      revealedAt: revealedAt,
      wisdomId: 'wisdom-1',
    ));

    expect(result.status, HomeKeepStatus.kept);
    expect(controller.items, [kept]);
    expect(captured.revealId, 'reveal-kept');
    expect(captured.revealedAt, revealedAt);
    expect(captured.wisdomId, 'wisdom-1');
  });

  test('limit and write failure both preserve the previous projection',
      () async {
    final existing = item('existing', 'reveal-existing');
    var mode = 0;
    final controller = HomeKeptController(
      loadItems: () async => [existing],
      keepWisdom: (_) async {
        if (mode == 0) {
          return const HomeKeptWriteResult(items: [], limitReached: true);
        }
        throw StateError('write failed');
      },
    );
    await controller.load();
    final request = HomeKeepRequest(
      text: 'Stay.',
      date: 'August 24, 2026',
      isKeeper: false,
      revealId: 'new',
      revealedAt: DateTime.utc(2026, 8, 24),
    );

    expect(
        (await controller.keep(request)).status, HomeKeepStatus.limitReached);
    expect(controller.items, [existing]);
    mode = 1;
    expect((await controller.keep(request)).status, HomeKeepStatus.failed);
    expect(controller.items, [existing]);
  });

  test('overlapping incoming refreshes are newest-wins', () async {
    final first = Completer<List<FavoriteItem>>();
    final second = Completer<List<FavoriteItem>>();
    var calls = 0;
    final controller = HomeKeptController(
      loadItems: () => calls++ == 0 ? first.future : second.future,
      keepWisdom: (_) async => throw UnimplementedError(),
    );

    final older = controller.refreshAfterIncomingChange();
    final newer = controller.refreshAfterIncomingChange();
    final newestItem = item('newest', 'reveal-newest');
    second.complete([newestItem]);
    expect(await newer, isTrue);
    first.complete([item('stale', 'reveal-stale')]);
    expect(await older, isFalse);
    expect(controller.items, [newestItem]);
  });

  test('dispose invalidates an in-flight incoming refresh', () async {
    final pending = Completer<List<FavoriteItem>>();
    final controller = HomeKeptController(
      loadItems: () => pending.future,
      keepWisdom: (_) async => throw UnimplementedError(),
    );

    final refresh = controller.refreshAfterIncomingChange();
    controller.dispose();
    pending.complete([item('late', 'reveal-late')]);

    expect(await refresh, isFalse);
    expect(controller.items, isEmpty);
  });
}
