import 'pixel_frame.dart';

class CaptureControls {
  static const zoomLevels = [4, 8, 12, 16, 24, 32];
  static const defaultZoom = 12;

  static int adjustZoom(int current, int steps) {
    final index = zoomLevels.indexOf(current);
    return zoomLevels[((index < 0 ? 2 : index) + steps).clamp(
      0,
      zoomLevels.length - 1,
    )];
  }

  static int adjustTolerance(int current, int steps) =>
      (current + steps * 15).clamp(0, 255);

  /// Return pixel centers so repeated nudges cannot accumulate fractional DPI error.
  static ({double x, double y}) nudge(
    PixelFrame frame,
    double x,
    double y,
    int dx,
    int dy,
  ) {
    final point = frame.logicalToPixel(x, y);
    return (
      x: ((point.x + dx).clamp(0, frame.width - 1) + .5) / frame.scaleX,
      y: ((point.y + dy).clamp(0, frame.height - 1) + .5) / frame.scaleY,
    );
  }
}
