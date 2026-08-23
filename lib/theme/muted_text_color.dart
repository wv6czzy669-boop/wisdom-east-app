import 'package:flutter/material.dart';

import 'east_design.dart';

/// A single muted, low-contrast tone reserved for a specific, explicitly
/// approved set of secondary labels (Home countdown, Kept metadata,
/// Reflection actions, Keeper copy, Settings tagline).
///
/// This is intentionally scoped: it is not a general "secondary text"
/// color and must not be applied to new call sites without the same
/// explicit approval that introduced it. See EAST_ARCHITECTURE_V1.md for
/// the broader design-system baseline.
///
/// Theme-reactive: resolves through [EastColors.of], so it follows
/// Appearance (System/Light/Dark) exactly like every other EAST. color.
/// The Light value remains pixel-identical to the original constant.
Color eastMutedTextColor(BuildContext context) =>
    EastColors.of(context).secondary;
