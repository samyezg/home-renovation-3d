import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../utils/image_orientation.dart';

/// 期次 AA/Z 共用：ROI 归一化几何与裁剪（无 Flutter UI 依赖）。
class RoiCrop {
  const RoiCrop({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left, top, right, bottom;
  double get width => right - left;
  double get height => bottom - top;
}

abstract final class RoiGeom {
  static RoiCrop boundingNorm(List<List<double>> poly) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in poly) {
      if (p.length < 2) continue;
      minX = math.min(minX, p[0]);
      minY = math.min(minY, p[1]);
      maxX = math.max(maxX, p[0]);
      maxY = math.max(maxY, p[1]);
    }
    return RoiCrop(
      left: minX.clamp(0.0, 1.0),
      top: minY.clamp(0.0, 1.0),
      right: maxX.clamp(0.0, 1.0),
      bottom: maxY.clamp(0.0, 1.0),
    );
  }

  /// 整图识别时用：坐标相对整图。
  static String promptSnippetFullImage(List<List<double>> poly) {
    final pts = poly
        .map((p) => '[${p[0].toStringAsFixed(3)},${p[1].toStringAsFixed(3)}]')
        .join(',');
    return '\n\n重要：用户已框选外轮廓 ROI（归一化多边形，相对整图）：[$pts]。'
        '请只识别该多边形内部的墙体/房间/门窗；框外内容一律忽略。'
        '输出坐标相对整图 0～1。';
  }

  /// 已裁剪送图时用：勿再要求「相对整图」。
  static String promptSnippetCropped() {
    return '\n\n重要：当前附图已是用户 ROI 裁剪图（框外已去除）。'
        '请识别图中全部户型结构；输出坐标相对本裁剪图 0～1。';
  }

  /// 裁剪 ROI 外接矩形；返回 JPEG 字节与裁剪区（归一化相对 bake 后原图）。
  static ({Uint8List bytes, RoiCrop cropNorm})? cropToJpeg(
    List<int> imageBytes,
    List<List<double>> roiPoly, {
    double padFrac = 0.02,
  }) {
    try {
      final decoded = ImageOrientation.decodeBaked(imageBytes);
      if (decoded == null) return null;
      final w = decoded.width;
      final h = decoded.height;
      final box = boundingNorm(roiPoly);
      final left = ((box.left - padFrac) * w).floor().clamp(0, w - 1);
      final top = ((box.top - padFrac) * h).floor().clamp(0, h - 1);
      final right = ((box.right + padFrac) * w).ceil().clamp(left + 1, w);
      final bottom = ((box.bottom + padFrac) * h).ceil().clamp(top + 1, h);
      final cw = right - left;
      final ch = bottom - top;
      final cropped = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: cw,
        height: ch,
      );
      final jpg = img.encodeJpg(cropped, quality: 88);
      return (
        bytes: Uint8List.fromList(jpg),
        cropNorm: RoiCrop(
          left: left / w,
          top: top / h,
          right: right / w,
          bottom: bottom / h,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static List<List<double>> mapPolyFromCrop(
    List<List<double>> cropPoly,
    RoiCrop cropNorm,
  ) {
    final bw = cropNorm.width;
    final bh = cropNorm.height;
    return [
      for (final p in cropPoly)
        if (p.length >= 2)
          [
            (cropNorm.left + p[0].clamp(0.0, 1.0) * bw).clamp(0.0, 1.0),
            (cropNorm.top + p[1].clamp(0.0, 1.0) * bh).clamp(0.0, 1.0),
          ],
    ];
  }

  static double mapXFromCrop(double x, RoiCrop cropNorm) =>
      (cropNorm.left + x.clamp(0.0, 1.0) * cropNorm.width).clamp(0.0, 1.0);

  static double mapYFromCrop(double y, RoiCrop cropNorm) =>
      (cropNorm.top + y.clamp(0.0, 1.0) * cropNorm.height).clamp(0.0, 1.0);
}
