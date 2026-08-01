import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelFileProtectionBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void setHandler(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  const bridge = MethodChannelFileProtectionBridge();

  test(
      '1. valid absolute path invokes the exact channel, method, and '
      'arguments', () async {
    MethodCall? captured;
    setHandler((call) async {
      captured = call;
      return true;
    });

    await bridge.protectAndVerifyComplete('/tmp/some/path.json');

    expect(captured, isNotNull);
    expect(captured!.method, MethodChannelFileProtectionBridge.methodName);
    expect(captured!.arguments, {'path': '/tmp/some/path.json'});
  });

  test('2. a true native result completes successfully', () async {
    setHandler((call) async => true);

    await expectLater(
      bridge.protectAndVerifyComplete('/tmp/a'),
      completes,
    );
  });

  test('3. a false native result throws FileProtectionException', () async {
    setHandler((call) async => false);

    await expectLater(
      bridge.protectAndVerifyComplete('/tmp/a'),
      throwsA(isA<FileProtectionException>()),
    );
  });

  test('4. a null native result throws FileProtectionException', () async {
    setHandler((call) async => null);

    await expectLater(
      bridge.protectAndVerifyComplete('/tmp/a'),
      throwsA(isA<FileProtectionException>()),
    );
  });

  test('5. a wrong-type native result throws FileProtectionException',
      () async {
    setHandler((call) async => 'true');

    await expectLater(
      bridge.protectAndVerifyComplete('/tmp/a'),
      throwsA(isA<FileProtectionException>()),
    );
  });

  test(
      '6. a PlatformException from the channel surfaces as a typed '
      'FileProtectionException', () async {
    setHandler((call) async {
      throw PlatformException(code: 'protection_apply_failed');
    });

    await expectLater(
      bridge.protectAndVerifyComplete('/tmp/a'),
      throwsA(isA<FileProtectionException>()),
    );
  });

  test(
      '7. a MissingPluginException (no native handler registered) surfaces '
      'as a typed FileProtectionException', () async {
    // Explicitly clear any handler to simulate no native implementation
    // being registered for this channel.
    messenger.setMockMethodCallHandler(channel, null);

    await expectLater(
      bridge.protectAndVerifyComplete('/tmp/a'),
      throwsA(isA<FileProtectionException>()),
    );
  });

  test('8. a blank path is rejected before invoking the channel', () async {
    var invoked = false;
    setHandler((call) async {
      invoked = true;
      return true;
    });

    await expectLater(
      bridge.protectAndVerifyComplete('   '),
      throwsA(isA<FileProtectionException>()),
    );
    expect(invoked, isFalse);
  });

  test('9. a relative path is rejected before invoking the channel', () async {
    var invoked = false;
    setHandler((call) async {
      invoked = true;
      return true;
    });

    await expectLater(
      bridge.protectAndVerifyComplete('relative/path.json'),
      throwsA(isA<FileProtectionException>()),
    );
    expect(invoked, isFalse);
  });
}
