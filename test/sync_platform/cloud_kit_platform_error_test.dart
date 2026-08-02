// Build 26 Phase 4B-1: CloudKitPlatformException -- reuse of the existing
// Phase 4A error classifier, and confirmation that no localized message is
// ever part of this type's shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/sync_error_classification.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_error.dart';

void main() {
  group(
      '1. category reuses the exact existing Phase 4A classifier -- no '
      'second, independently-maintained classification scheme', () {
    test('a known retryable code classifies as retryable', () {
      const error = CloudKitPlatformException(syncErrorCodeNetworkUnavailable);
      expect(error.category, SyncErrorCategory.retryable);
    });

    test('a known account-issue code classifies as accountIssue', () {
      const error = CloudKitPlatformException(syncErrorCodeNotAuthenticated);
      expect(error.category, SyncErrorCategory.accountIssue);
    });

    test(
        'an unrecognized code (e.g. this layer\'s own fallback codes) '
        'classifies as permanent -- fail closed, matching '
        'classifySyncErrorCode\'s own documented default', () {
      const error = CloudKitPlatformException(
          CloudKitPlatformException.unrecognizedNativeErrorCode);
      expect(error.category, SyncErrorCategory.permanent);
      expect(
        error.category,
        classifySyncErrorCode(
            CloudKitPlatformException.unrecognizedNativeErrorCode),
      );
    });
  });

  group(
      '2. this type never carries a raw/localized message -- only a '
      'symbolic code field exists at all', () {
    test('toString contains only the symbolic code, never a message', () {
      const error = CloudKitPlatformException('someCode');
      expect(error.toString(), 'CloudKitPlatformException(someCode)');
    });
  });

  test('equality and hashCode are code-based', () {
    const a = CloudKitPlatformException('someCode');
    const b = CloudKitPlatformException('someCode');
    const c = CloudKitPlatformException('otherCode');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
