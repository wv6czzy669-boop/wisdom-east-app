import 'package:flutter/services.dart';

/// StoreKit 2's verified entitlement result. [unavailable] is intentionally
/// distinct from [notEntitled]: only the former permits a last-known local
/// cache to keep the UI usable while the native bridge cannot answer.
enum KeeperEntitlementAuthorityResult {
  entitled,
  notEntitled,
  unavailable,
}

abstract interface class KeeperEntitlementAuthority {
  Future<KeeperEntitlementAuthorityResult> currentEntitlement();
}

final class MethodChannelKeeperEntitlementAuthority
    implements KeeperEntitlementAuthority {
  const MethodChannelKeeperEntitlementAuthority();

  static const String channelName =
      'com.dogukan.dailywisdom/keeper_entitlement';
  static const String methodName = 'currentKeeperEntitlement';
  static const MethodChannel channel = MethodChannel(channelName);

  @override
  Future<KeeperEntitlementAuthorityResult> currentEntitlement() async {
    try {
      final entitled = await channel.invokeMethod<bool>(methodName);
      if (entitled == null) return KeeperEntitlementAuthorityResult.unavailable;
      return entitled
          ? KeeperEntitlementAuthorityResult.entitled
          : KeeperEntitlementAuthorityResult.notEntitled;
    } on MissingPluginException {
      return KeeperEntitlementAuthorityResult.unavailable;
    } on PlatformException {
      return KeeperEntitlementAuthorityResult.unavailable;
    } catch (_) {
      return KeeperEntitlementAuthorityResult.unavailable;
    }
  }
}
