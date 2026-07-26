import 'package:flutter/material.dart';

/// A quiet slide transition that opens/closes a route from a chosen screen
/// edge instead of the platform-default direction.
///
/// Used so the Settings route can enter from the left (matching the
/// top-left hamburger control that opens it) while Objects and Kept keep
/// their existing platform-default (right-origin, on iOS) behavior by
/// continuing to use a plain `MaterialPageRoute` untouched by this class.
class DirectionalPageRoute<T> extends PageRouteBuilder<T> {
  DirectionalPageRoute({
    required WidgetBuilder builder,
    required this.beginOffset,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: _duration,
          reverseTransitionDuration: _duration,
        );

  /// The default Flutter/Material page-route transition duration (also the
  /// value `MaterialPageRoute` uses), kept identical here so the new
  /// direction does not also change how long the transition takes.
  static const Duration _duration = Duration(milliseconds: 300);

  /// Where the incoming page starts, in fractional-of-viewport terms (e.g.
  /// `Offset(-1, 0)` for a left-origin push, `Offset(1, 0)` for the
  /// platform-default right-origin push).
  final Offset beginOffset;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedOffset = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.linearToEaseOut));

    return SlideTransition(
      position: animation.drive(curvedOffset),
      child: child,
    );
  }
}
