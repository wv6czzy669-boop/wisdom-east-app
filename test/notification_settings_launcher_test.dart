import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/services/notification_settings_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('east.productions/notification_settings');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
      'on a non-iOS platform the channel is never touched and the result '
      'is false', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      return true;
    });

    final launcher = MethodChannelNotificationSettingsLauncher(
      channel: channel,
    );

    expect(await launcher.openNotificationSettings(), isFalse);
    expect(invoked, isFalse);
  });

  test(
      'on iOS, invokes exactly the one narrow "openNotificationSettings" '
      'method and returns a true channel response as-is', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var invokedMethod = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      invokedMethod = call.method;
      return true;
    });

    final launcher = MethodChannelNotificationSettingsLauncher(
      channel: channel,
    );

    expect(await launcher.openNotificationSettings(), isTrue);
    expect(invokedMethod, 'openNotificationSettings');
  });

  test('on iOS, a false channel response is returned as-is', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => false);

    final launcher = MethodChannelNotificationSettingsLauncher(
      channel: channel,
    );

    expect(await launcher.openNotificationSettings(), isFalse);
  });

  test('on iOS, a null channel response is treated as false', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final launcher = MethodChannelNotificationSettingsLauncher(
      channel: channel,
    );

    expect(await launcher.openNotificationSettings(), isFalse);
  });

  test(
      'on iOS, a thrown PlatformException (e.g. a missing or misbehaving '
      'host implementation) is contained and never crashes the caller',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });

    final launcher = MethodChannelNotificationSettingsLauncher(
      channel: channel,
    );

    expect(await launcher.openNotificationSettings(), isFalse);
  });

  test(
      'on iOS, a MissingPluginException (no host handler registered) is '
      'contained and never crashes the caller', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // No mock handler registered at all: invoking the channel throws
    // MissingPluginException, exactly like a host app that has not wired
    // up the AppDelegate.swift handler.
    final launcher = MethodChannelNotificationSettingsLauncher(
      channel: channel,
    );

    expect(await launcher.openNotificationSettings(), isFalse);
  });
}
