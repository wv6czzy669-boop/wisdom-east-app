import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/objects_catalog.dart';
import '../theme/muted_text_color.dart';
import '../widgets/east_back_button.dart';
import '../widgets/objects/looping_product_gallery.dart';
import '../widgets/objects/tshirt_color_selector.dart';

typedef ObjectsUrlLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

/// A single, vertically scrollable, editorial discovery page for the two
/// current EAST. Objects (the T-Shirt and the Tote Bag). This screen is
/// discovery-only: no price, no checkout, no product-detail routes. The
/// single "Discover the Objects" action continues the experience on
/// east.productions.
class ObjectsScreen extends StatefulWidget {
  const ObjectsScreen({
    super.key,
    this.urlLauncher,
  });

  final ObjectsUrlLauncher? urlLauncher;

  @override
  State<ObjectsScreen> createState() => _ObjectsScreenState();
}

class _ObjectsScreenState extends State<ObjectsScreen> {
  TshirtColor _selectedColor = TshirtColor.espresso;
  bool _discoverLaunchInProgress = false;

  TextStyle _style(
    double size, {
    Color color = const Color(0xFFF4F0E8),
    double height = 1.35,
    double letterSpacing = 0.4,
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF111111),
          content: Text(message, style: _style(17)),
        ),
      );
  }

  Future<bool> _launchExternal(Uri uri, {required LaunchMode mode}) {
    final launcher = widget.urlLauncher;
    if (launcher != null) {
      return launcher(uri, mode: mode);
    }
    return launchUrl(uri, mode: mode);
  }

  Future<void> _openDiscoverObjects() async {
    if (_discoverLaunchInProgress || !mounted) return;

    setState(() {
      _discoverLaunchInProgress = true;
    });

    try {
      final uri = Uri.parse(ObjectsCatalog.discoverObjectsUrl);
      final launched = await _launchExternal(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!launched) {
        _showMessage('The Objects page could not be opened.');
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage('The Objects page could not be opened.');
    } finally {
      if (mounted) {
        setState(() {
          _discoverLaunchInProgress = false;
        });
      }
    }
  }

  void _selectColor(TshirtColor color) {
    if (color == _selectedColor) return;
    setState(() {
      _selectedColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final galleryHeight = (screenHeight * 0.48).clamp(260.0, 460.0);
    final tshirtGallery = ObjectsCatalog.galleryFor(_selectedColor);

    return Scaffold(
      key: const ValueKey('objects-screen-root'),
      backgroundColor: const Color(0xFF040404),
      appBar: AppBar(
        backgroundColor: const Color(0xFF040404),
        foregroundColor: const Color(0xFFF4F0E8),
        iconTheme: const IconThemeData(
          color: Color(0xFFF4F0E8),
          size: 22,
          weight: 300,
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Navigator.canPop(context) ? const EastBackButton() : null,
        title: Text('Objects', style: _style(24)),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 20, bottom: 56),
          child: Column(
            children: [
              Text(ObjectsCatalog.tshirtName, style: _style(22)),
              const SizedBox(height: 24),
              FractionallySizedBox(
                widthFactor: 0.88,
                child: LoopingProductGallery(
                  key: ValueKey(_selectedColor),
                  height: galleryHeight,
                  images: tshirtGallery,
                  semanticsLabelBuilder: (index) =>
                      '${ObjectsCatalog.tshirtName}, '
                      '${ObjectsCatalog.colorLabel(_selectedColor)}, '
                      'image ${index + 1} of ${tshirtGallery.length}',
                ),
              ),
              const SizedBox(height: 26),
              TshirtColorSelector(
                selected: _selectedColor,
                onChanged: _selectColor,
              ),
              const SizedBox(height: 92),
              Text(ObjectsCatalog.toteName, style: _style(22)),
              const SizedBox(height: 24),
              FractionallySizedBox(
                widthFactor: 0.88,
                child: LoopingProductGallery(
                  key: const ValueKey('objects-tote-gallery'),
                  height: galleryHeight,
                  images: ObjectsCatalog.toteGallery,
                  semanticsLabelBuilder: (index) =>
                      '${ObjectsCatalog.toteName}, '
                      'image ${index + 1} of ${ObjectsCatalog.toteGallery.length}',
                ),
              ),
              const SizedBox(height: 64),
              FractionallySizedBox(
                widthFactor: 0.88,
                child: Divider(
                  color: eastMutedTextColor.withValues(alpha: 0.30),
                  thickness: 0.5,
                ),
              ),
              const SizedBox(height: 28),
              Semantics(
                button: true,
                label: _discoverLaunchInProgress
                    ? 'Discover the Objects. Opening.'
                    : 'Discover the Objects. Opens east.productions in your browser.',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    key: const ValueKey('objects-discover-action'),
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        _discoverLaunchInProgress ? null : _openDiscoverObjects,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Center(
                        child: Text(
                          'DISCOVER THE OBJECTS',
                          textAlign: TextAlign.center,
                          style: _style(
                            15.5,
                            color: eastMutedTextColor,
                            letterSpacing: 2.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
