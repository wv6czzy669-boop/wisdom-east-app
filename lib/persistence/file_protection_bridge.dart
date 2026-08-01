import 'package:flutter/services.dart';

/// Applies, and verifies, `NSFileProtectionComplete` on a file or directory.
///
/// This is not a general native filesystem abstraction — it exposes
/// exactly the one operation the Phase 3B protected file store needs.
/// [MethodChannelFileProtectionBridge] is the production implementation;
/// tests inject a fake so `flutter test` never depends on a real native
/// handler.
abstract interface class FileProtectionBridge {
  /// Applies `NSFileProtectionComplete` to the file or directory at [path]
  /// and reads the attribute back to confirm it actually took effect.
  ///
  /// [path] must identify an existing file or directory. Successful
  /// completion means the native side both applied the protection *and*
  /// read it back successfully — a call that merely fails to throw from
  /// the underlying attribute-setting call is not sufficient on its own.
  /// Any failure — a missing path, a native apply failure, a native
  /// read-back/verification failure, or an unreachable native handler —
  /// must throw.
  Future<void> protectAndVerifyComplete(String path);
}

/// Thrown by [FileProtectionBridge] implementations on any failure to
/// apply or verify file protection.
class FileProtectionException implements Exception {
  const FileProtectionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'FileProtectionException: $message';
    return 'FileProtectionException: $message ($cause)';
  }
}

/// Production [FileProtectionBridge], backed by a single native
/// `MethodChannel` call per [protectAndVerifyComplete] invocation.
///
/// Never no-ops on a non-iOS platform: if the native side has no handler
/// registered for [channelName]/[methodName] (for example, running on a
/// platform with no such native implementation), that surfaces as a
/// [FileProtectionException] via [MissingPluginException], exactly like any
/// other failure — this bridge never silently pretends to succeed.
final class MethodChannelFileProtectionBridge implements FileProtectionBridge {
  const MethodChannelFileProtectionBridge();

  static const String channelName = 'com.dogukan.dailywisdom/file_protection';
  static const String methodName = 'protectAndVerifyComplete';

  static const MethodChannel _channel = MethodChannel(channelName);

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    if (path.trim().isEmpty) {
      throw const FileProtectionException(
        'File protection path cannot be blank.',
      );
    }
    if (!path.startsWith('/')) {
      throw const FileProtectionException(
        'File protection path must be absolute.',
      );
    }

    dynamic rawResult;
    try {
      rawResult = await _channel.invokeMethod(methodName, {'path': path});
    } on MissingPluginException catch (error) {
      throw FileProtectionException(
        'File protection channel is unavailable.',
        error,
      );
    } on PlatformException catch (error) {
      throw FileProtectionException(
        'File protection failed: ${error.code}',
        error,
      );
    } catch (error) {
      throw FileProtectionException(
        'File protection failed unexpectedly.',
        error,
      );
    }

    if (rawResult is! bool || rawResult != true) {
      throw const FileProtectionException(
        'File protection did not return a successful result.',
      );
    }
  }
}
