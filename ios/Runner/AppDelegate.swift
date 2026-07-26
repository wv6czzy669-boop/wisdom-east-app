import Flutter
import UIKit
import UserNotifications

// The narrow channel name shared with the Dart-side default in
// `lib/services/notification_settings_launcher.dart`
// (`MethodChannelNotificationSettingsLauncher`). Keep both in sync if this
// ever changes.
private let notificationSettingsChannelName = "east.productions/notification_settings"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNotificationSettingsChannel(using: engineBridge.applicationRegistrar.messenger())
  }

  /// Answers the single `openNotificationSettings` method used by the Daily
  /// Reminder Settings row when OS-level notification authorization is
  /// already denied. Deliberately narrow: this channel does nothing else.
  ///
  /// Uses the official `UIApplication.openNotificationSettingsURLString` to
  /// deep-link straight to EAST.'s own notification-settings page. Xcode's
  /// actual SDK availability annotation for this constant requires iOS
  /// 16.0 (confirmed by the real release-build compiler error: "'open
  /// NotificationSettingsURLString' is only available in iOS 16.0 or
  /// newer" — this project does not raise its iOS 13.0 deployment target
  /// to match), so the call is guarded with `#available(iOS 16.0, *)` and
  /// falls back to the documented, always-available `UIApplication
  /// .openSettingsURLString` (the app's general Settings page) on every
  /// older iOS version this project still supports.
  private func registerNotificationSettingsChannel(using messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: notificationSettingsChannelName,
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "openNotificationSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let urlString: String
      if #available(iOS 16.0, *) {
        urlString = UIApplication.openNotificationSettingsURLString
      } else {
        urlString = UIApplication.openSettingsURLString
      }

      guard let url = URL(string: urlString) else {
        result(false)
        return
      }

      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { success in
          result(success)
        }
      }
    }
  }
}
