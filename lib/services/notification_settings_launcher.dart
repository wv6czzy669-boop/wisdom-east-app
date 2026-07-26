import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Opens the running app's own notification-settings page in the system
/// Settings app.
///
/// Kept as its own narrow abstraction, separate from
/// [WisdomNotificationPlatform], so the Dart-facing call site
/// (`WisdomNotificationService.openNotificationSettings`) can be exercised
/// in widget/service tests via a fake without ever invoking a real
/// `MethodChannel`.
abstract interface class NotificationSettingsLauncher {
  /// Returns whether the settings page was actually opened. Never throws:
  /// implementations must treat every failure (missing platform channel,
  /// non-iOS platform, a thrown platform exception) as a `false` result.
  Future<bool> openNotificationSettings();
}

/// Default implementation. Invokes a single, narrowly scoped
/// `MethodChannel` method (`openNotificationSettings`) that the iOS host
/// (`ios/Runner/AppDelegate.swift`) answers by constructing the URL from
/// the official `UIApplication.openNotificationSettingsURLString` (iOS
/// 16.0+, per Xcode's actual SDK availability annotation), falling back to
/// the documented `UIApplication.openSettingsURLString` on every older iOS
/// version still supported by this project's iOS 13.0 deployment target.
/// No undocumented URL scheme is ever hard-coded on the Dart side, and no
/// new package dependency is used — this is a plain `MethodChannel`, part
/// of the Flutter SDK already used throughout this app.
class MethodChannelNotificationSettingsLauncher
    implements NotificationSettingsLauncher {
  MethodChannelNotificationSettingsLauncher({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'east.productions/notification_settings',
  );

  final MethodChannel _channel;

  @override
  Future<bool> openNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      return result ?? false;
    } catch (_) {
      // A missing/failing platform channel must never crash the app; the
      // Daily Reminder row simply stays in its current state.
      return false;
    }
  }
}
