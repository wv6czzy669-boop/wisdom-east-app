import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';

void main() {
  late DateTime now;
  late _FakeNotificationPlatform platform;
  late WisdomNotificationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2041, 7, 23, 8);
    platform = _FakeNotificationPlatform(enabled: true);
    service = WisdomNotificationService(
      platform: platform,
      clock: () => now,
    );
  });

  test('successful reveal replaces one schedule at exact unlock instant',
      () async {
    final unlockAt = now.add(const Duration(hours: 24));

    await service.scheduleFromAuthoritativeUnlock(unlockAt);

    expect(platform.events, [
      'cancel:${WisdomNotificationService.unlockNotificationId}',
      'schedule:${WisdomNotificationService.unlockNotificationId}',
    ]);
    expect(platform.schedules, hasLength(1));
    final schedule = platform.schedules.single;
    expect(schedule.title, 'EAST.');
    expect(schedule.body, 'Something waits in silence.');
    expect(
      schedule.unlockAt.millisecondsSinceEpoch,
      unlockAt.millisecondsSinceEpoch,
    );
  });

  test('past unlock and ready status cancel without scheduling', () async {
    await service.scheduleFromAuthoritativeUnlock(
      now.subtract(const Duration(seconds: 1)),
    );
    await service.synchronizeWithStatus(
      const DailyWisdomStatus(isReady: true),
    );

    expect(platform.schedules, isEmpty);
    expect(
      platform.events.where((event) => event.startsWith('cancel:')).length,
      2,
    );
  });

  test('locked startup sync replaces the exact authoritative schedule',
      () async {
    final unlockAt = now.add(const Duration(hours: 7));
    await service.synchronizeWithStatus(
      DailyWisdomStatus(
        isReady: false,
        unlockAt: unlockAt,
        remaining: const Duration(hours: 7),
        lockedText: 'Existing wisdom.',
      ),
    );

    expect(platform.schedules.single.unlockAt, unlockAt);
  });

  test('repeated startup sync keeps one stable native notification identity',
      () async {
    final unlockAt = now.add(const Duration(hours: 7));
    final status = DailyWisdomStatus(
      isReady: false,
      unlockAt: unlockAt,
      remaining: const Duration(hours: 7),
    );

    await service.synchronizeWithStatus(status);
    await service.synchronizeWithStatus(status);

    expect(platform.schedules, hasLength(2));
    expect(
      platform.schedules.map((schedule) => schedule.id).toSet(),
      {WisdomNotificationService.unlockNotificationId},
    );
    expect(platform.events, [
      'cancel:${WisdomNotificationService.unlockNotificationId}',
      'schedule:${WisdomNotificationService.unlockNotificationId}',
      'cancel:${WisdomNotificationService.unlockNotificationId}',
      'schedule:${WisdomNotificationService.unlockNotificationId}',
    ]);
  });

  test('startup synchronization never mutates daily wisdom access', () async {
    const dailyAccess = '{"authoritative":"unchanged"}';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': dailyAccess,
    });

    await service.synchronizeWithStatus(
      DailyWisdomStatus(
        isReady: false,
        unlockAt: now.add(const Duration(hours: 7)),
        remaining: const Duration(hours: 7),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('daily_wisdom_access'), dailyAccess);
  });

  test('transient platform initialization failure remains retryable', () async {
    platform.failInitializationOnce = true;

    expect(
      await service.authorizationStatus(),
      WisdomNotificationAuthorization.unavailable,
    );
    expect(
      await service.authorizationStatus(),
      WisdomNotificationAuthorization.authorized,
    );
    expect(platform.initializationAttempts, 2);
  });

  test('startup never requests permission while status is not determined',
      () async {
    platform.enabled = false;
    final unlockAt = now.add(const Duration(hours: 24));

    await service.synchronizeWithStatus(
      DailyWisdomStatus(
        isReady: false,
        unlockAt: unlockAt,
        remaining: const Duration(hours: 24),
      ),
    );

    expect(await service.shouldOfferPermission(), isTrue);
    expect(platform.permissionRequests, 0);
    expect(platform.schedules, isEmpty);
  });

  test(
      'launch/resume sync never requests permission and schedules nothing '
      'while the system is denied', () async {
    platform.enabled = false;
    await service.dismissPermissionOffer();
    final unlockAt = now.add(const Duration(hours: 24));

    await service.synchronizeWithStatus(
      DailyWisdomStatus(
        isReady: false,
        unlockAt: unlockAt,
        remaining: const Duration(hours: 24),
      ),
    );

    expect(
      await service.authorizationStatus(),
      WisdomNotificationAuthorization.denied,
    );
    expect(platform.permissionRequests, 0);
    expect(platform.schedules, isEmpty);
  });

  test(
      'authorization changed from denied to authorized in system Settings '
      'is detected and scheduled on the next resume, without duplicate '
      'scheduling', () async {
    platform.enabled = false;
    await service.dismissPermissionOffer();
    final unlockAt = now.add(const Duration(hours: 24));
    final status = DailyWisdomStatus(
      isReady: false,
      unlockAt: unlockAt,
      remaining: const Duration(hours: 24),
    );

    // First resume: still denied — nothing scheduled, nothing requested.
    await service.synchronizeWithStatus(status);
    expect(platform.permissionRequests, 0);
    expect(platform.schedules, isEmpty);

    // The user enables notifications for EAST. from the iOS Settings app,
    // then returns to EAST. — the next resume sync must pick this up.
    platform.enabled = true;
    await service.synchronizeWithStatus(status);

    expect(platform.permissionRequests, 0);
    expect(platform.schedules, hasLength(1));
    expect(platform.schedules.single.unlockAt, unlockAt);

    // A further resume with the same authoritative status must not
    // duplicate the schedule.
    await service.synchronizeWithStatus(status);
    expect(platform.schedules, hasLength(2));
    expect(
      platform.schedules.map((schedule) => schedule.id).toSet(),
      {WisdomNotificationService.unlockNotificationId},
    );
  });

  test('dismissing pre-permission offer prevents repeated offers', () async {
    platform.enabled = false;

    expect(await service.shouldOfferPermission(), isTrue);
    await service.dismissPermissionOffer();
    expect(await service.shouldOfferPermission(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(WisdomNotificationService.permissionPromptHandledKey),
      isTrue,
    );

    final relaunchedService = WisdomNotificationService(
      platform: _FakeNotificationPlatform(enabled: false),
      clock: () => now,
    );
    expect(await relaunchedService.shouldOfferPermission(), isFalse);
  });

  test('accepting permission requests once and schedules exact unlock',
      () async {
    platform.enabled = false;
    platform.permissionResult = true;
    final unlockAt = now.add(const Duration(hours: 24));

    expect(
      await service.requestPermissionAndSchedule(unlockAt),
      isTrue,
    );

    expect(platform.permissionRequests, 1);
    expect(platform.schedules.single.unlockAt, unlockAt);
  });

  test('permission denial remains nonfatal and does not schedule', () async {
    platform.enabled = false;
    platform.permissionResult = false;

    expect(
      await service.requestPermissionAndSchedule(
        now.add(const Duration(hours: 24)),
      ),
      isFalse,
    );
    expect(platform.permissionRequests, 1);
    expect(platform.schedules, isEmpty);
    expect(await service.shouldOfferPermission(), isFalse);
  });

  test('scheduling failure is contained', () async {
    platform.scheduleError = StateError('native scheduling failed');

    await service.scheduleFromAuthoritativeUnlock(
      now.add(const Duration(hours: 24)),
    );

    expect(platform.scheduleAttempts, 1);
  });

  test('overlapping replacements serialize and leave newest schedule last',
      () async {
    final firstUnlock = now.add(const Duration(hours: 24));
    final secondUnlock = now.add(const Duration(hours: 25));
    platform.firstScheduleGate = Completer<void>();

    final first = service.scheduleFromAuthoritativeUnlock(firstUnlock);
    await platform.firstScheduleStarted.future;
    final second = service.scheduleFromAuthoritativeUnlock(secondUnlock);

    expect(platform.scheduleAttempts, 1);
    platform.firstScheduleGate!.complete();
    await Future.wait([first, second]);

    expect(platform.schedules.map((item) => item.unlockAt), [
      firstUnlock,
      secondUnlock,
    ]);
    expect(platform.schedules.last.unlockAt, secondUnlock);
  });

  group(
      'requestPermissionAndSchedule is the canonical reveal-time direct '
      'path, gated purely on system authorization', () {
    test(
        'notDetermined: the reveal-time path requests native permission '
        'directly, exactly once, and schedules once granted', () async {
      platform.enabled = false;
      platform.permissionResult = true;
      final unlockAt = now.add(const Duration(hours: 24));

      final result = await service.requestPermissionAndSchedule(unlockAt);

      expect(result, isTrue);
      expect(platform.permissionRequests, 1);
      expect(platform.schedules.single.unlockAt, unlockAt);
    });

    test(
        'notDetermined + denial: schedules nothing and requests permission '
        'only once, with no custom UI', () async {
      platform.enabled = false;
      platform.permissionResult = false;

      final result = await service.requestPermissionAndSchedule(
        now.add(const Duration(hours: 24)),
      );

      expect(result, isFalse);
      expect(platform.permissionRequests, 1);
      expect(platform.schedules, isEmpty);
      expect(await service.shouldOfferPermission(), isFalse);
    });

    test('authorized: scheduling remains allowed', () async {
      platform.enabled = true;
      final unlockAt = now.add(const Duration(hours: 24));

      await service.scheduleFromAuthoritativeUnlock(unlockAt);

      expect(platform.schedules.single.unlockAt, unlockAt);
    });

    test(
        'authorized: scheduling remains allowed, and permission is not '
        'requested again since the OS already granted it', () async {
      platform.enabled = true;
      final permissionRequestsBeforeSchedule = platform.permissionRequests;

      final unlockAt = now.add(const Duration(hours: 24));
      final result = await service.requestPermissionAndSchedule(unlockAt);

      expect(result, isTrue);
      expect(platform.schedules.single.unlockAt, unlockAt);
      expect(platform.permissionRequests, permissionRequestsBeforeSchedule);
    });

    test(
        'denied (prompt previously handled): does not request permission '
        'again and stays silent', () async {
      platform.enabled = false;
      await service.dismissPermissionOffer();

      final result = await service.requestPermissionAndSchedule(
        now.add(const Duration(hours: 24)),
      );

      expect(result, isFalse);
      expect(platform.permissionRequests, 0);
      expect(platform.schedules, isEmpty);
    });
  });
}

class _FakeNotificationPlatform implements WisdomNotificationPlatform {
  _FakeNotificationPlatform({
    required this.enabled,
  });

  bool enabled;
  bool permissionResult = false;
  Object? scheduleError;
  Completer<void>? firstScheduleGate;
  final Completer<void> firstScheduleStarted = Completer<void>();
  int permissionRequests = 0;
  int initializationAttempts = 0;
  int scheduleAttempts = 0;
  bool failInitializationOnce = false;
  final List<String> events = [];
  final List<_ScheduledNotification> schedules = [];

  @override
  Future<void> initialize() async {
    initializationAttempts += 1;
    if (failInitializationOnce) {
      failInitializationOnce = false;
      throw StateError('initialization failed');
    }
  }

  @override
  Future<bool?> notificationsEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    if (permissionResult) enabled = true;
    return permissionResult;
  }

  @override
  Future<void> cancel(int id) async {
    events.add('cancel:$id');
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  }) async {
    scheduleAttempts += 1;
    if (scheduleAttempts == 1 && !firstScheduleStarted.isCompleted) {
      firstScheduleStarted.complete();
      await firstScheduleGate?.future;
    }
    final error = scheduleError;
    if (error != null) throw error;
    events.add('schedule:$id');
    schedules.add(
      _ScheduledNotification(
        id: id,
        title: title,
        body: body,
        unlockAt: unlockAt,
      ),
    );
  }
}

class _ScheduledNotification {
  const _ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.unlockAt,
  });

  final int id;
  final String title;
  final String body;
  final DateTime unlockAt;
}
