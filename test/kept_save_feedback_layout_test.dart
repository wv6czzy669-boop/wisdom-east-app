import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/services/first_ritual_guidance_service.dart';
import 'package:wisdom_app/services/kept_discovery_hint_service.dart';
import 'package:wisdom_app/services/rating_request_service.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/theme/east_design.dart';
import 'persistence_test_helpers.dart';

const _captureDirectory = String.fromEnvironment('EAST_CAPTURE_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Frame export uses runAsync, which also lets native plugin initialization
    // finish. Supply silent platform channels; this test exercises Home layout.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events'
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(channel), (_) async => null);
    }
    messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'), (call) async {
      if (call.method == 'create') {
        final playerId = (call.arguments as Map)['playerId'];
        messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$playerId'),
            (_) async => null);
      }
      return null;
    });
  });
  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
    InAppPurchasePlatform.instance = _NoopPurchasePlatform();
    for (final font in EastTypographyResolver.productionFonts) {
      await (FontLoader(font.family)..addFont(rootBundle.load(font.asset)))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  testWidgets(
      'saved confirmation and press-and-hold labels fit every locale, theme and large type',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundaryKey = GlobalKey();
    Future<void> capture(String name) async {
      if (_captureDirectory.isEmpty) return;
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_captureDirectory/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          final captureView = _captureDirectory.isNotEmpty &&
              scale == 1 &&
              ['tr', 'en', 'ar', 'ja'].contains(locale.languageCode);
          final width = captureView ? 390.0 : 320.0;
          tester.view.physicalSize = Size(width * 2, 844 * 2);
          tester.view.devicePixelRatio = 2;
          final now = DateTime.utc(2026, 9, 6, 10);
          final graph = KeptRepositoryTestGraph(clock: () => now);
          final daily = DailyAccessTestGraph(clock: () => now);
          SharedPreferences.setMockInitialValues({
            'daily_wisdom_access': DailyWisdomRecord(
              text: const WisdomLocalizationResolver().resolve(
                wisdomId: 'east_wisdom_0059',
                locale: locale,
                persistedSnapshot: 'Peace enters slowly.',
              )!,
              revealedAt: now,
              unlockAt: now.add(const Duration(hours: 24)),
              revealId: 'aaaaaaaa-0000-4000-8000-000000000001',
            ).encode(),
            KeptDiscoveryHintService.completedKey: true,
            KeptDiscoveryHintService.keptNavDiscoveryCompletedKey: true,
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: eastTheme(locale: locale, brightness: brightness),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        padding: const EdgeInsets.only(top: 54, bottom: 34)),
                    child: child!),
                home: HomeScreen(
                    savedReflectionsService: graph.service,
                    dailyWisdomAccessService: daily.service,
                    clock: () => now,
                    keptDiscoveryHintService: KeptDiscoveryHintService(),
                    firstRitualGuidanceService: FirstRitualGuidanceService(),
                    ratingRequestService: RatingRequestService()),
              )));
          for (final ms in [450, 950, 550]) {
            await tester.pump(Duration(milliseconds: ms));
          }
          await tester.tapAt(Offset(width / 2, 422));
          for (final ms in [850, 1200, 1100, 100]) {
            await tester.pump(Duration(milliseconds: ms));
          }
          final save = find.byKey(const ValueKey('home-save-control-unsaved'));
          final nav = find.byKey(const ValueKey('home-kept-control'));
          final ringBefore = tester.getRect(save),
              navBefore = tester.getRect(nav);
          final hold = await tester.startGesture(tester.getCenter(save));
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byKey(const ValueKey('keep-control-help-text')),
              findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: '$locale / $brightness / $scale help');
          final stem = '${locale.languageCode}-${brightness.name}';
          if (captureView) await capture('$stem-save-help');
          await hold.up();
          await tester.pump();
          final navHold = await tester.startGesture(tester.getCenter(nav));
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.byKey(const ValueKey('kept-control-help-text')),
              findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: '$locale / $brightness / $scale Kept help');
          if (captureView) await capture('$stem-kept-help');
          await navHold.up();
          await tester.pump();
          if (captureView) await capture('$stem-before');
          await tester.tap(save);
          await tester.pump();
          await tester.pump();
          if (captureView && locale.languageCode == 'tr') {
            for (var frame = 0; frame <= 45; frame++) {
              await capture('$stem-frame-${frame.toString().padLeft(3, '0')}');
              await tester.pump(const Duration(milliseconds: 40));
              if (frame == 15) await capture('$stem-saved');
            }
          } else {
            await tester.pump(const Duration(milliseconds: 600));
            expect(find.text(l10n.reflectionSaved), findsOneWidget);
            final label = tester
                .getRect(find.byKey(const ValueKey('keep-save-feedback-text')));
            expect(label.left, greaterThanOrEqualTo(0));
            expect(label.right, lessThanOrEqualTo(width));
            expect(label.bottom, lessThan(810));
            expect(label.overlaps(ringBefore), isFalse);
            if (captureView) await capture('$stem-saved');
          }
          expect(
              tester.getRect(
                  find.byKey(const ValueKey('home-save-control-kept'))),
              ringBefore);
          expect(tester.getRect(nav), navBefore);
          expect(tester.takeException(), isNull,
              reason: '$locale / $brightness / $scale');
          await tester.pump(const Duration(seconds: 2));
          expect(find.byKey(const ValueKey('keep-save-feedback-text')),
              findsNothing);
          expect(find.byKey(const ValueKey('kept-save-feedback-breath')),
              findsNothing);
        }
      }
    }
  });
}

class _NoopPurchasePlatform extends InAppPurchasePlatform {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<bool> isAvailable() async => false;
}
