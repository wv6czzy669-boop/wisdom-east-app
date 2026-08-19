import 'package:flutter/material.dart';

/// EAST. app-wide back-navigation control.
///
/// Real-device repair: replaces the implicit `AppBar` back button (which
/// Flutter builds internally as a `BackButton` widget whenever
/// `automaticallyImplyLeading` is true, `leading` is null, and the route can
/// pop) everywhere across the app. That internal `BackButton` always sets
/// `tooltip: MaterialLocalizations.of(context).backButtonTooltip`, which is
/// exactly what produces the white "Back" popover on a long press --
/// `IconButton` only wraps itself in a `Tooltip` when a non-null `tooltip`
/// is supplied, so omitting the parameter entirely (never passing `''`,
/// which would still show an empty tooltip box) removes that wrapper.
///
/// Two things the removed `Tooltip` used to do implicitly are restored
/// explicitly here, matching the same correction already applied to Home's
/// own top-navigation controls (`_HomeTopNavigation` in
/// `home_ritual_widgets.dart`):
///  - accessibility: an explicit `Semantics(label: 'Back', button: true)`
///    node, so VoiceOver/TalkBack still understand the control as "Back"
///    even with no `Tooltip` contributing that label itself.
///  - gesture arena: `Tooltip` used to also claim a long press outright
///    (to show itself), so a long press on the old back button was always a
///    real no-op for navigation. Without it, an unclaimed long press falls
///    through to `IconButton`'s own tap recognizer as an ordinary
///    slow tap-and-release, which would fire real navigation mid long
///    press. The no-op `onLongPress` below claims that gesture instead, so
///    a long press is still a no-op and only a normal tap navigates.
///
/// Visual (the `BackButtonIcon`, same platform-adaptive glyph Flutter's own
/// `BackButton` uses), hit target (a plain `IconButton`, unchanged size/
/// padding), and navigation (`Navigator.maybePop`, the same call
/// `BackButton` itself makes) are otherwise identical to the button this
/// replaces.
class EastBackButton extends StatelessWidget {
  const EastBackButton({super.key, this.onPressed});

  /// Overridable only for tests; production always falls back to the
  /// default `Navigator.maybePop(context)`, exactly like Flutter's own
  /// [BackButton].
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = onPressed ?? () => Navigator.maybePop(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {},
      excludeFromSemantics: true,
      child: Semantics(
        label: 'Back',
        button: true,
        onTap: effectiveOnPressed,
        child: ExcludeSemantics(
          child: IconButton(
            key: const ValueKey('east-back-button'),
            icon: const BackButtonIcon(),
            onPressed: effectiveOnPressed,
          ),
        ),
      ),
    );
  }
}
