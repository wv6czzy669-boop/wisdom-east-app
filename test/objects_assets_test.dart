import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/objects_catalog.dart';

void main() {
  final allDeclaredAssets = <String>{
    ...ObjectsCatalog.espressoGallery,
    ...ObjectsCatalog.khakiGallery,
    ...ObjectsCatalog.toteGallery,
    ObjectsCatalog.espressoButtonAsset,
    ObjectsCatalog.khakiButtonAsset,
  };

  test('every declared Objects asset path exists on disk', () {
    for (final path in allDeclaredAssets) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Missing declared asset: $path',
      );
    }
  });

  test(
      'exactly 8 optimized Objects assets are declared, matching the '
      'approved reduced set (espresso_3, khaki_3, tote_3, and tote_4 '
      'removed)', () {
    expect(allDeclaredAssets, hasLength(8));
    for (final removed in [
      'assets/objects/espresso_3.webp',
      'assets/objects/khaki_3.webp',
      'assets/objects/tote_3.webp',
      'assets/objects/tote_4.webp',
    ]) {
      expect(
        allDeclaredAssets.contains(removed),
        isFalse,
        reason: '$removed should no longer be declared in ObjectsCatalog',
      );
      expect(
        File(removed).existsSync(),
        isFalse,
        reason: '$removed should have been deleted from the repository',
      );
    }
  });

  test('no declared asset path contains spaces or uppercase letters', () {
    for (final path in allDeclaredAssets) {
      expect(path.contains(' '), isFalse, reason: '$path contains a space');
      expect(
        path,
        path.toLowerCase(),
        reason: '$path is not fully lowercase',
      );
    }
  });

  test(
      'the assets/objects directory contains only the declared optimized '
      'derivatives — no original 1MB source PNG photo was registered', () {
    final dir = Directory('assets/objects');
    expect(dir.existsSync(), isTrue);

    final shippedFiles = dir
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll('\\', '/'))
        .toList();

    for (final shipped in shippedFiles) {
      expect(
        allDeclaredAssets.any((declared) => shipped.endsWith(declared)),
        isTrue,
        reason: '$shipped is present in assets/objects but not declared in '
            'ObjectsCatalog',
      );
    }

    // The 10 product photographs must be WebP derivatives, never the
    // original ~1MB PNG photos.
    final productPhotoAssets = [
      ...ObjectsCatalog.espressoGallery,
      ...ObjectsCatalog.khakiGallery,
      ...ObjectsCatalog.toteGallery,
    ];
    for (final path in productPhotoAssets) {
      expect(path.endsWith('.webp'), isTrue);
      final size = File(path).lengthSync();
      expect(
        size,
        lessThan(500 * 1024),
        reason: '$path is $size bytes — suspiciously large for an '
            'optimized derivative; an unoptimized original may have been '
            'copied in by mistake.',
      );
    }

    // The two color-swatch controls must stay small (tiny tap-target
    // artwork, not full-resolution source renders).
    for (final path in [
      ObjectsCatalog.espressoButtonAsset,
      ObjectsCatalog.khakiButtonAsset,
    ]) {
      final size = File(path).lengthSync();
      expect(
        size,
        lessThan(50 * 1024),
        reason: '$path is $size bytes — larger than expected for a small '
            'circular color control.',
      );
    }
  });

  test('Tote gallery normalized filenames preserve the approved source order',
      () {
    // tote_1..tote_2 correspond, in order, to Tote2, Tote1.
    expect(ObjectsCatalog.toteGallery, [
      'assets/objects/tote_1.webp',
      'assets/objects/tote_2.webp',
    ]);
  });

  test('Espresso and Khaki galleries are reduced to exactly two images each',
      () {
    expect(ObjectsCatalog.espressoGallery, hasLength(2));
    expect(ObjectsCatalog.khakiGallery, hasLength(2));
  });
}
