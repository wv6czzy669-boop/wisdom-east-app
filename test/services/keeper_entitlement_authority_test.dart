import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/services/keeper_entitlement_authority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const authority = MethodChannelKeeperEntitlementAuthority();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannelKeeperEntitlementAuthority.channel,
      null,
    );
  });

  for (final scenario in <bool, KeeperEntitlementAuthorityResult>{
    true: KeeperEntitlementAuthorityResult.entitled,
    false: KeeperEntitlementAuthorityResult.notEntitled,
  }.entries) {
    test('maps native ${scenario.key} to ${scenario.value.name}', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannelKeeperEntitlementAuthority.channel,
        (call) async {
          expect(
            call.method,
            MethodChannelKeeperEntitlementAuthority.methodName,
          );
          return scenario.key;
        },
      );

      expect(await authority.currentEntitlement(), scenario.value);
    });
  }

  test('missing or failed native authority is explicitly unavailable',
      () async {
    expect(
      await authority.currentEntitlement(),
      KeeperEntitlementAuthorityResult.unavailable,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannelKeeperEntitlementAuthority.channel,
      (_) async => throw PlatformException(code: 'store_unavailable'),
    );
    expect(
      await authority.currentEntitlement(),
      KeeperEntitlementAuthorityResult.unavailable,
    );
  });
}
