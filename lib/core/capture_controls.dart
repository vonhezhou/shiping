import 'pixel_frame.dart';
import 'ruler.dart';

class CaptureControls {
  static PixelRect? suggestedRect(
    PixelFrame frame,
    Object? value,
    double x,
    double y,
  ) {
    if (value is! Map) return null;
    final l = value['left'],
        t = value['top'],
        r = value['right'],
        b = value['bottom'];
    if (l is! int ||
        t is! int ||
        r is! int ||
        b is! int ||
        l < 0 ||
        t < 0 ||
        r > frame.width ||
        b > frame.height ||
        r <= l ||
        b <= t) {
      return null;
    }
    final p = frame.logicalToPixel(x, y);
    if (p.x < l || p.x >= r || p.y < t || p.y >= b) return null;
    return PixelRect(left: l, top: t, right: r, bottom: b);
  }

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
