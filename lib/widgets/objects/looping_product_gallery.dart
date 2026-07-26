import 'package:flutter/material.dart';

/// A manually-swiped, infinitely-looping, single-image-per-page gallery.
///
/// There are no dots, counters, arrows, or autoplay: position is exposed
/// only through accessibility semantics via [semanticsLabelBuilder].
///
/// To reset to the first image of a new image set (for example, when the
/// user changes the EAST. T-Shirt color), give this widget a new `key` from
/// the parent — a fresh `Key` causes Flutter to discard the old State
/// (and its `PageController`) and mount a new one, which reliably starts
/// at the first image again. This widget does not attempt to detect an
/// in-place image-list change itself.
class LoopingProductGallery extends StatefulWidget {
  const LoopingProductGallery({
    super.key,
    required this.images,
    required this.semanticsLabelBuilder,
    this.height,
  });

  final List<String> images;
  final String Function(int index) semanticsLabelBuilder;
  final double? height;

  @override
  State<LoopingProductGallery> createState() => LoopingProductGalleryState();
}

class LoopingProductGalleryState extends State<LoopingProductGallery> {
  // Large enough that no realistic amount of manual swiping reaches either
  // end, giving the appearance of an unbroken loop in both directions.
  static const int _loopSpan = 100000;

  late final PageController _controller;

  // A multiple of `images.length`, so `initialPage % images.length == 0`
  // and the gallery always starts on the first image of the set.
  int get _initialPage => widget.images.length * (_loopSpan ~/ 2);

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _controller,
        itemBuilder: (context, index) {
          final actualIndex = index % images.length;
          return Semantics(
            image: true,
            label: widget.semanticsLabelBuilder(actualIndex),
            child: ExcludeSemantics(
              child: Image.asset(
                images[actualIndex],
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
