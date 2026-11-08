import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 涂抹笔迹 → 局部替换 mask（白=可改，黑=保留）。
abstract final class RenovMask {
  /// [strokes] 为相对图 0～1 的折线；[brushNorm] 为相对短边的笔刷半径（约 0.02～0.08）。
  static Uint8List bakePng({
    required int width,
    required int height,
    required List<List<List<double>>> strokes,
    double brushNorm = 0.045,
  }) {
    final mask = img.Image(width: width, height: height);
    img.fill(mask, color: img.ColorRgb8(0, 0, 0));
    final r = math.max(2, (math.min(width, height) * brushNorm).round());
    final white = img.ColorRgb8(255, 255, 255);
    for (final s in strokes) {
      if (s.isEmpty) continue;
      for (var i = 0; i < s.length; i++) {
        final x = (s[i][0].clamp(0.0, 1.0) * (width - 1)).round();
        final y = (s[i][1].clamp(0.0, 1.0) * (height - 1)).round();
        img.fillCircle(mask, x: x, y: y, radius: r, color: white);
        if (i > 0) {
          _thickLine(
            mask,
            x0: (s[i - 1][0].clamp(0.0, 1.0) * (width - 1)).round(),
            y0: (s[i - 1][1].clamp(0.0, 1.0) * (height - 1)).round(),
            x1: x,
            y1: y,
            radius: r,
            color: white,
          );
        }
      }
    }
    return Uint8List.fromList(img.encodePng(mask));
  }

  /// 用 mask 合成：圈外保留 [base]，圈内取 [edited]（边缘轻羽化）。
  static Uint8List composite({
    required Uint8List baseBytes,
    required Uint8List editedBytes,
    required Uint8List maskPng,
  }) {
    final base = img.decodeImage(baseBytes);
    final edited = img.decodeImage(editedBytes);
    final mask = img.decodeImage(maskPng);
    if (base == null || edited == null || mask == null) {
      return editedBytes;
    }
    final w = base.width;
    final h = base.height;
    final ed = (edited.width == w && edited.height == h)
        ? edited
        : img.copyResize(edited, width: w, height: h);
    final mk = (mask.width == w && mask.height == h)
        ? mask
        : img.copyResize(mask, width: w, height: h);
    final out = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final m = mk.getPixel(x, y).r / 255.0;
        final a = _smoothstep(m);
        final b = base.getPixel(x, y);
        final e = ed.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          (b.r * (1 - a) + e.r * a).round().clamp(0, 255),
          (b.g * (1 - a) + e.g * a).round().clamp(0, 255),
          (b.b * (1 - a) + e.b * a).round().clamp(0, 255),
          255,
        );
      }
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: 90));
  }

  /// 无 API 时：仅在 mask 内做风格色调混合（示意，非 AI）。
  static Uint8List localTintInMask({
    required Uint8List baseBytes,
    required Uint8List maskPng,
    required int swatchArgb,
  }) {
    final base = img.decodeImage(baseBytes);
    final mask = img.decodeImage(maskPng);
    if (base == null || mask == null) return baseBytes;
    final w = base.width;
    final h = base.height;
    final mk = (mask.width == w && mask.height == h)
        ? mask
        : img.copyResize(mask, width: w, height: h);
    final r = (swatchArgb >> 16) & 0xFF;
    final g = (swatchArgb >> 8) & 0xFF;
    final b = swatchArgb & 0xFF;
    final out = img.Image.from(base);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = _smoothstep(mk.getPixel(x, y).r / 255.0) * 0.35;
        if (a < 0.01) continue;
        final p = out.getPixel(x, y);
        out.setPixelRgba(
          x,
          y,
          (p.r * (1 - a) + r * a).round().clamp(0, 255),
          (p.g * (1 - a) + g * a).round().clamp(0, 255),
          (p.b * (1 - a) + b * a).round().clamp(0, 255),
          255,
        );
      }
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: 90));
  }

  static bool hasCoverage(Uint8List maskPng, {double minRatio = 0.002}) {
    final mask = img.decodeImage(maskPng);
    if (mask == null) return false;
    var lit = 0;
    final total = mask.width * mask.height;
    for (final p in mask) {
      if (p.r > 40) lit++;
    }
    return total > 0 && lit / total >= minRatio;
  }

  static double _smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static void _thickLine(
    img.Image mask, {
    required int x0,
    required int y0,
    required int x1,
    required int y1,
    required int radius,
    required img.Color color,
  }) {
    final dx = x1 - x0;
    final dy = y1 - y0;
    final steps = math.max(1, math.max(dx.abs(), dy.abs()));
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x0 + dx * t).round();
      final y = (y0 + dy * t).round();
      img.fillCircle(mask, x: x, y: y, radius: radius, color: color);
    }
  }
}
