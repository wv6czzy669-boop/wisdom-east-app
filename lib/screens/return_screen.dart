import 'package:flutter/material.dart';

import '../models/favorite_item.dart';
import '../widgets/east_back_button.dart';

/// EAST. Phase 9 — Return's own dedicated, read-only display screen.
///
/// Deliberately not the daily ritual screen and not [ReflectionScreen]
/// (../reflection_screen.dart): no reveal animation, no autosave, no Save/
/// Edit affordance of any kind — this only ever displays an
/// already-existing Kept occurrence, resolved and handed to this screen by
/// its caller ([SavedReflectionsScreen]) via [item]. This widget never
/// talks to [SavedReflectionsService]/[ReturnService] itself, never
/// selects, reselects, or mutates anything.
///
/// Visual-polish repair: [item] is now nullable. A `null` [item] renders
/// the quiet, minimal pre-eligibility explanation state instead of an
/// occurrence — reachable by both Free and Keeper, never gated, since it
/// only ever explains what Return is rather than exposing any actual
/// content.
class ReturnScreen extends StatelessWidget {
  const ReturnScreen({super.key, this.item});

  final FavoriteItem? item;

  TextStyle _style(
    double size, {
    Color color = const Color(0xFFF4F0E8),
    double height = 1.4,
    double letterSpacing = 0.35,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = item;
    return Scaffold(
      backgroundColor: const Color(0xFF040404),
      appBar: AppBar(
        backgroundColor: const Color(0xFF040404),
        foregroundColor: const Color(0xFFF4F0E8),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        // Real-device repair: Return is a peer surface to Objects/Kept/
        // Journal, so its title now lives in the same page-title/nav
        // hierarchy as theirs (a real AppBar title, not a small in-body
        // marker), with the same trailing period dropped as Journal's.
        title: Text('Return',
            key: const ValueKey('return-title'), style: _style(24)),
      ),
      body: SafeArea(
        top: false,
        // Approved Ritual direction ("Return — empty"): with nothing yet
        // eligible, the explanation takes the optical centre of the
        // remaining body -- no ring, no ornament, no divider, just the
        // negative space around one line. An actual occurrence keeps the
        // original scrolling, left-set archive composition untouched.
        child: currentItem == null
            ? Center(
                // Deliberately extremely minimal: no lock icon, no
                // countdown, no progress bar, no promotional card, no
                // "upgrade" language, no feature list, no notification CTA
                // -- this only ever explains the mechanic, available
                // identically to Free and Keeper.
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'What you keep may return after 14 days.',
                    key: const ValueKey('return-explanation-copy'),
                    textAlign: TextAlign.center,
                    style: _style(
                      20,
                      color: const Color(0xE6FFFFFF),
                      height: 1.5,
                    ),
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentItem.date.toUpperCase(),
                      key: const ValueKey('return-original-date'),
                      style: _style(
                        15,
                        color: const Color(0xB3FFFFFF),
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      currentItem.text,
                      key: const ValueKey('return-original-wisdom'),
                      style: _style(24, height: 1.46),
                    ),
                    if (currentItem.hasReflection) ...[
                      const SizedBox(height: 42),
                      Text(
                        currentItem.reflection!,
                        key: const ValueKey('return-original-reflection'),
                        style: _style(
                          20,
                          color: const Color(0xE6FFFFFF),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
