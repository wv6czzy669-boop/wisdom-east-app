/// Fixed, local content for the EAST. Objects screen.
///
/// This is intentionally a plain data holder: no network, no backend model,
/// no pricing/inventory concepts. The Objects screen is a discovery-only
/// surface for exactly two current products; the website is the
/// continuation of the experience (see DISCOVER_OBJECTS_URL).
library;

/// The two available EAST. T-Shirt colors.
enum TshirtColor { espresso, khaki }

class ObjectsCatalog {
  const ObjectsCatalog._();

  /// External destination for the single "Discover the Objects" action.
  static const String discoverObjectsUrl = 'https://east.productions/objects';

  static const String tshirtName = 'EAST. T-Shirt';
  static const String toteName = 'EAST. Tote Bag';

  // Optimized WebP derivatives of Espresso1/2.png, in display order.
  static const List<String> espressoGallery = [
    'assets/objects/espresso_1.webp',
    'assets/objects/espresso_2.webp',
  ];

  // Optimized WebP derivatives of Khaki1/2.png. Update 2: Khaki2.png is now
  // first (index 0 / the initial selected image for Khaki); Khaki1.png
  // remains available immediately after it.
  static const List<String> khakiGallery = [
    'assets/objects/khaki_2.webp',
    'assets/objects/khaki_1.webp',
  ];

  // Optimized WebP derivatives, in the approved display order:
  // Tote2.png, Tote1.png.
  static const List<String> toteGallery = [
    'assets/objects/tote_1.webp', // Tote2.png
    'assets/objects/tote_2.webp', // Tote1.png
  ];

  static const String espressoButtonAsset =
      'assets/objects/espresso_button.png';
  static const String khakiButtonAsset = 'assets/objects/khaki_button.png';

  static List<String> galleryFor(TshirtColor color) {
    switch (color) {
      case TshirtColor.espresso:
        return espressoGallery;
      case TshirtColor.khaki:
        return khakiGallery;
    }
  }

  static String colorLabel(TshirtColor color) {
    switch (color) {
      case TshirtColor.espresso:
        return 'Espresso';
      case TshirtColor.khaki:
        return 'Khaki';
    }
  }
}
