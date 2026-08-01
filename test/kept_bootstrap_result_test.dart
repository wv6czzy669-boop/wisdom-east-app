import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';

void main() {
  group('ready', () {
    test('ready has status ready and a null errorCode', () {
      const result = KeptBootstrapResult.ready();

      expect(result.status, KeptBootstrapStatus.ready);
      expect(result.errorCode, isNull);
      expect(result.isReady, isTrue);
      expect(result.isUnavailable, isFalse);
    });

    test('ready is constructible as a compile-time constant', () {
      const first = KeptBootstrapResult.ready();
      const second = KeptBootstrapResult.ready();

      expect(identical(first, second), isTrue);
    });
  });

  group('unavailable', () {
    test('unavailable has status unavailable and the supplied errorCode', () {
      final result =
          KeptBootstrapResult.unavailable('protected-store-load-failed');

      expect(result.status, KeptBootstrapStatus.unavailable);
      expect(result.errorCode, 'protected-store-load-failed');
      expect(result.isReady, isFalse);
      expect(result.isUnavailable, isTrue);
    });

    test('a blank errorCode is rejected', () {
      expect(
        () => KeptBootstrapResult.unavailable(''),
        throwsArgumentError,
      );
    });

    test('a whitespace-only errorCode is rejected', () {
      expect(
        () => KeptBootstrapResult.unavailable('   '),
        throwsArgumentError,
      );
    });
  });

  group('content safety', () {
    test(
        'toString() never includes anything beyond status/errorCode -- in '
        'particular, it is never asked to carry wisdom or reflection text', () {
      final result = KeptBootstrapResult.unavailable('load-failure');

      expect(result.toString(), contains('load-failure'));
      expect(result.toString(), isNot(contains('/')));
    });
  });

  group('equality', () {
    test('two ready results are equal', () {
      expect(
        const KeptBootstrapResult.ready(),
        const KeptBootstrapResult.ready(),
      );
    });

    test('two unavailable results with the same errorCode are equal', () {
      expect(
        KeptBootstrapResult.unavailable('load-failure'),
        KeptBootstrapResult.unavailable('load-failure'),
      );
    });

    test('two unavailable results with different errorCodes are not equal', () {
      expect(
        KeptBootstrapResult.unavailable('load-failure') ==
            KeptBootstrapResult.unavailable('replace-failure'),
        isFalse,
      );
    });

    test('a ready result and an unavailable result are never equal', () {
      expect(
        const KeptBootstrapResult.ready() ==
            KeptBootstrapResult.unavailable('load-failure'),
        isFalse,
      );
    });

    test('equal instances share the same hashCode', () {
      expect(
        KeptBootstrapResult.unavailable('load-failure').hashCode,
        KeptBootstrapResult.unavailable('load-failure').hashCode,
      );
    });
  });
}
