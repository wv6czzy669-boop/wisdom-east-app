import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract interface class PrivateWritingLockBridge {
  Future<Map<Object?, Object?>> status();
  Future<bool> authenticate(String reason);
  Future<Map<Object?, Object?>> setEnabled(bool enabled, String reason);
  Future<void> setSensitive(bool value);
  Future<void> protectedFrameReady();
}

final class MethodChannelPrivateWritingLockBridge
    implements PrivateWritingLockBridge {
  static const channel = MethodChannel('east/private_writing_lock');
  @override
  Future<Map<Object?, Object?>> status() async =>
      await channel.invokeMapMethod<Object?, Object?>('status') ?? {};
  @override
  Future<bool> authenticate(String reason) async =>
      await channel.invokeMethod<bool>('authenticate', {'reason': reason}) ==
      true;
  @override
  Future<Map<Object?, Object?>> setEnabled(bool enabled, String reason) async =>
      await channel.invokeMapMethod<Object?, Object?>(
          'setEnabled', {'enabled': enabled, 'reason': reason}) ??
      {};
  @override
  Future<void> setSensitive(bool value) =>
      channel.invokeMethod('sensitive', {'value': value});
  @override
  Future<void> protectedFrameReady() => channel.invokeMethod('frameReady');
}

/// The session belongs to a foreground visit to private writing. It is never
/// persisted or shared with the widget, Keeper entitlement or ritual clock.
class PrivateWritingLockController extends ChangeNotifier
    with WidgetsBindingObserver {
  PrivateWritingLockController(
      {PrivateWritingLockBridge? bridge, bool? supportedPlatform})
      : _bridge = bridge ?? MethodChannelPrivateWritingLockBridge(),
        _supportedPlatform =
            supportedPlatform ?? (bridge != null || Platform.isIOS) {
    if (!_supportedPlatform) _loaded = true;
    WidgetsBinding.instance.addObserver(this);
  }

  static final shared = PrivateWritingLockController();
  final PrivateWritingLockBridge _bridge;
  final bool _supportedPlatform;
  final Set<Object> _scopes = {};
  bool _loaded = false, _enabled = false, _available = false;
  bool _unlocked = false, _busy = false, _foreground = true, _disposed = false;
  bool _failed = false;
  int _generation = 0;
  Future<void>? _loading;
  Future<void>? _visibilityTail;
  Completer<void>? _foregroundChange;

  bool get loaded => _loaded;
  bool get enabled => _enabled;
  bool get available => _available;
  bool get busy => _busy;
  bool get failed => _failed;
  bool get canRead => _loaded && (!_enabled || (_unlocked && _foreground));

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _readStatus(Map<Object?, Object?> value) {
    if (value['enabled'] is! bool || value['available'] is! bool) {
      throw const FormatException('Invalid writing lock status.');
    }
    _enabled = value['enabled'] as bool;
    _available = value['available'] as bool;
    _loaded = true;
  }

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> refresh() async {
    if (_supportedPlatform && !_busy) await _load();
  }

  Future<void> _load() async {
    try {
      _readStatus(await _bridge.status().timeout(const Duration(seconds: 4)));
      _failed = false;
    } catch (_) {
      // A missing/failed iOS bridge cannot silently turn an existing lock off.
      _failed = true;
    }
    _changed();
  }

  Future<void> enter(Object scope) async {
    _scopes.add(scope);
    await load();
    if (_supportedPlatform) {
      _visibilityTail = (_visibilityTail ?? Future<void>.value())
          .catchError((_) {})
          .then((_) => _bridge.setSensitive(_scopes.isNotEmpty));
      await _visibilityTail;
    }
  }

  void leave(Object scope) {
    _scopes.remove(scope);
    if (_scopes.isEmpty) {
      _generation++;
      _unlocked = false;
      _foregroundChange?.complete();
      _foregroundChange = null;
    }
    if (_supportedPlatform) {
      _visibilityTail = (_visibilityTail ?? Future<void>.value())
          .catchError((_) {})
          .then((_) => _bridge.setSensitive(_scopes.isNotEmpty));
      unawaited(_visibilityTail!.catchError((_) {}));
    }
    // Gate disposal runs during a widget-tree update. Remaining gates rebuild
    // on the next lifecycle/authentication event, not inside that update.
  }

  Future<bool> unlock(String reason) async {
    await load();
    if (canRead) return true;
    if (!_loaded || _busy || !_foreground) return false;
    _busy = true;
    _failed = false;
    final generation = _generation;
    _changed();
    try {
      final authenticated = await _bridge.authenticate(reason);
      if (authenticated && generation == _generation && !_disposed) {
        _unlocked = true;
        // LocalAuthentication may complete before UIKit sends resumed. Keep
        // an export waiting for that foreground visit, without prompting twice.
        while (!_foreground && generation == _generation && !_disposed) {
          await (_foregroundChange ??= Completer<void>()).future;
        }
      }
      return authenticated &&
          generation == _generation &&
          !_disposed &&
          canRead;
    } catch (_) {
      _failed = true;
      return false;
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<bool> changeEnabled(bool value, String reason) async {
    await load();
    if (!_loaded || _busy || !_foreground) return false;
    _busy = true;
    _failed = false;
    _changed();
    try {
      final result = await _bridge.setEnabled(value, reason);
      _readStatus(result);
      _unlocked = false;
      return result['authenticated'] == true && _enabled == value;
    } catch (_) {
      _failed = true;
      return false;
    } finally {
      _busy = false;
      _changed();
    }
  }

  void _acknowledgeProtectedFrame() {
    if (!_supportedPlatform) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _foreground) {
        unawaited(_bridge.protectedFrameReady().catchError((_) {}));
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _unlocked = false;
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        _generation++;
      }
    }
    _foregroundChange?.complete();
    _foregroundChange = null;
    _changed();
    if (_foreground) {
      _acknowledgeProtectedFrame();
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _foregroundChange?.complete();
    _foregroundChange = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
