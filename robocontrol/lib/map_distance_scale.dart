/// Formats an image-space distance using the map scale calibrated by
/// Measurement. Until a valid scale exists, the value remains explicitly in
/// pixels so it cannot be mistaken for a real-world distance.
String formatMapDistance(double pixels, double? metersPerPixel) {
  if (metersPerPixel == null ||
      !metersPerPixel.isFinite ||
      metersPerPixel <= 0) {
    return '${pixels.toStringAsFixed(1)} px';
  }
  return '${(pixels * metersPerPixel).toStringAsFixed(2)} m';
}
