import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../persistence/storage_preferences_adapter.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import 'daily_wisdom_access_service.dart';

enum WisdomNotificationAuthorization {
  notDetermined,
  authorized,
  denied,
  unavailable,
}

/// Explicit, deterministic copy dependency for code that has no BuildContext.
/// A later locale controller can supply a locale-specific [AppLocalizations]
/// instance without coupling this service to widget state.
class WisdomNotificationCopy {
  const WisdomNotificationCopy(this.localizations);

  factory WisdomNotificationCopy.english() =>
      WisdomNotificationCopy(AppLocalizationsEn());

  final AppLocalizations localizations;

  String get title => localizations.notificationTitle;
  String get body => localizations.notificationBody;
}

abstract interface class WisdomNotificationPlatform {
  Future<void> initialize();

  Future<bool?> notificationsEnabled();

  Future<bool> requestPermission();

  Future<void> cancel(int id);

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  });
}

class LocalWisdomNotificationPlatform implements WisdomNotificationPlatform {
  LocalWisdomNotificationPlatform({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialization;
  timezone.Location _location = timezone.UTC;

  @override
  Future<void> initialize() async {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _initialize();
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  Future<void> _initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    timezone_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      _location = timezone.getLocation(localTimezone.identifier);
      timezone.setLocalLocation(_location);
    } catch (_) {
      _location = timezone.UTC;
      timezone.setLocalLocation(timezone.UTC);
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: IOSInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool?> notificationsEnabled() async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final permissions = await ios?.checkPermissions();
    return permissions?.isEnabled;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(
          alert: true,
          sound: true,
          badge: false,
        ) ??
        false;
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  }) async {
    await initialize();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: timezone.TZDateTime.from(unlockAt, _location),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          threadIdentifier: 'east-wisdom-unlock',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}

class WisdomNotificationService {
  WisdomNotificationService({
    WisdomNotificationPlatform? platform,
    StoragePreferencesAdapter? preferencesAdapter,
    DateTime Function()? clock,
    WisdomNotificationCopy? copy,
  })  : _platform = platform ?? LocalWisdomNotificationPlatform(),
        _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter(),
        _clock = clock ?? DateTime.now,
        _copy = copy ?? WisdomNotificationCopy.english();

  static const int unlockNotificationId = 21001;
  static const String permissionPromptHandledKey =
      'wisdom_unlock_notification_prompt_handled';

  final WisdomNotificationPlatform _platform;
  final StoragePreferencesAdapter _preferencesAdapter;
  final DateTime Function() _clock;
  final WisdomNotificationCopy _copy;

  bool _promptHandledInMemory = false;
  Future<void>? _initialization;
  Future<void> _operationTail = Future<void>.value();

  Future<void> initialize() async {
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _platform.initialize();
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  Future<WisdomNotificationAuthorization> authorizationStatus() async {
    try {
      await initialize();
      final enabled = await _platform.notificationsEnabled();
      if (enabled == true) {
        return WisdomNotificationAuthorization.authorized;
      }
      if (enabled == null) {
        return WisdomNotificationAuthorization.unavailable;
      }

      final handled = _promptHandledInMemory ||
          (await _preferencesAdapter.getBool(permissionPromptHandledKey) ??
              false);
      return handled
          ? WisdomNotificationAuthorization.denied
          : WisdomNotificationAuthorization.notDetermined;
    } catch (_) {
      return WisdomNotificationAuthorization.unavailable;
    }
  }

  Future<bool> shouldOfferPermission() async {
    return await authorizationStatus() ==
        WisdomNotificationAuthorization.notDetermined;
  }

  Future<void> dismissPermissionOffer() async {
    await _markPromptHandled();
  }

  /// The single entry point Home calls at the approved reveal-time trigger
  /// when [shouldOfferPermission] was true.
  ///
  /// If the OS already reports `authorized` (for example, from an earlier
  /// reveal), this must not re-request native permission — iOS never shows
  /// a second system prompt once decided, and repeating the request here
  /// served no purpose and broke the "authorized" fast path. Scheduling
  /// happens directly in that case. Only when the OS status is genuinely
  /// `notDetermined` does this request permission first.
  Future<bool> requestPermissionAndSchedule(DateTime unlockAt) async {
    try {
      final status = await authorizationStatus();
      if (status == WisdomNotificationAuthorization.authorized) {
        await _serialize(() => _replaceSchedule(unlockAt));
        return true;
      }
      if (status != WisdomNotificationAuthorization.notDetermined) {
        // denied/unavailable: nothing more can be done from this entry
        // point without the user visiting system Settings.
        return false;
      }
      await _markPromptHandled();
      await initialize();
      final granted = await _platform.requestPermission();
      if (!granted) return false;
      await _serialize(() => _replaceSchedule(unlockAt));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Called after a fresh reveal to schedule (or clear) the reminder
  /// against the newly-committed authoritative unlock time. Never requests
  /// permission — only the OS-authorized state (already granted, from an
  /// earlier reveal or resume) results in an actual schedule.
  Future<void> scheduleFromAuthoritativeUnlock(DateTime unlockAt) async {
    try {
      await _serialize(() async {
        if (!unlockAt.isAfter(_clock())) {
          await _cancelNative();
          return;
        }
        if (await authorizationStatus() !=
            WisdomNotificationAuthorization.authorized) {
          return;
        }
        await _replaceSchedule(unlockAt);
      });
    } catch (_) {
      // Notification failures must never affect a successful wisdom reveal.
    }
  }

  /// Called on app launch and resume to reconcile the scheduled local
  /// notification against the live system authorization status and the
  /// authoritative current unlock record. Never requests permission — a
  /// `notDetermined` status is left for the approved reveal-time trigger.
  /// A `denied` status silently skips scheduling (and cancels any stale
  /// pending reminder once the unlock is no longer valid) rather than
  /// prompting or opening system Settings.
  Future<void> synchronizeWithStatus(DailyWisdomStatus status) async {
    try {
      await _serialize(() async {
        final unlockAt = status.unlockAt;
        if (status.isReady || unlockAt == null || !unlockAt.isAfter(_clock())) {
          await _cancelNative();
          return;
        }
        if (await authorizationStatus() !=
            WisdomNotificationAuthorization.authorized) {
          return;
        }
        await _replaceSchedule(unlockAt);
      });
    } catch (_) {
      // Startup synchronization is best-effort.
    }
  }

  Future<void> cancelUnlockNotification() async {
    try {
      await _serialize(_cancelNative);
    } catch (_) {
      // Stale notification cleanup is best-effort.
    }
  }

  Future<void> _replaceSchedule(DateTime unlockAt) async {
    if (!unlockAt.isAfter(_clock())) {
      await _cancelNative();
      return;
    }
    await _platform.cancel(unlockNotificationId);
    await _platform.schedule(
      id: unlockNotificationId,
      title: _copy.title,
      body: _copy.body,
      unlockAt: unlockAt,
    );
  }

  Future<void> _cancelNative() async {
    await initialize();
    await _platform.cancel(unlockNotificationId);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then(
      (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      onError: (_) async {
        try {
          completer.complete(await operation());
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  Future<void> _markPromptHandled() async {
    _promptHandledInMemory = true;
    try {
      await _preferencesAdapter.setBool(permissionPromptHandledKey, true);
    } catch (_) {
      // The in-memory guard still prevents repeated prompts in this session.
    }
  }
}
