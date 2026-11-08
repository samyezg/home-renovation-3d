import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../utils/image_orientation.dart';
import 'floorplan_models.dart';

/// 期次 Z：ROI 内几何精校（方案 D 后半段）。
///
/// 仅在 ROI（人工框或房间外包）内做边缘/正交线段检测，
/// 回写房间 polygon 边；失败保留模型坐标并写入 warning。
/// 禁止全局线检。
class RoiEdgeRefiner {
  /// [roiNorm] 人工框选多边形（可选）；缺省时用房间外包扩边。
  static Future<FloorplanAiResult> refine(
    FloorplanAiResult input,
    List<int> imageBytes, {
    List<List<double>>? roiNorm,
  }) async {
    try {
      final decoded = ImageOrientation.decodeBaked(imageBytes);
      if (decoded == null) {
        return _withWarning(input, 'ROI 精校跳过：无法解码图片');
      }
      final w = decoded.width;
      final h = decoded.height;
      if (w < 32 || h < 32 || input.rooms.isEmpty) {
        return _withWarning(input, 'ROI 精校跳过：图面或房间不足');
      }

      final roi = roiNorm != null && roiNorm.length >= 3
          ? roiNorm
          : _roomsOuterRoi(input.rooms);
      final box = _bounding(roi);
      // 略扩边，避免贴边墙被裁掉
      final pad = 0.03;
      final left = ((box.left - pad) * w).floor().clamp(0, w - 1);
      final top = ((box.top - pad) * h).floor().clamp(0, h - 1);
      final right = ((box.right + pad) * w).ceil().clamp(left + 1, w);
      final bottom = ((box.bottom + pad) * h).ceil().clamp(top + 1, h);
      final cw = right - left;
      final ch = bottom - top;

      final crop = img.copyCrop(
        decoded,
        x: left,
        y: top,
        width: cw,
        height: ch,
      );
      final gray = img.grayscale(crop);
      final segs = _detectOrthoSegments(gray);
      if (segs.isEmpty) {
        return _withWarning(input, 'ROI 精校：框内未检出可用线段，保留模型坐标');
      }

      // 线段转整图归一化
      final normSegs = <_Seg>[
        for (final s in segs)
          _Seg(
            (left + s.x1) / w,
            (top + s.y1) / h,
            (left + s.x2) / w,
            (top + s.y2) / h,
          ),
      ];

      final short = math.min(w, h).toDouble();
      final matchTol = 0.045; // 相对短边约 4.5%
      var snappedEdges = 0;

      final newRooms = <AiRoom>[];
      for (final room in input.rooms) {
        if (room.polygon.length < 3) {
          newRooms.add(room);
          continue;
        }
        final pts = [
          for (final p in room.polygon)
            if (p.length >= 2) [p[0], p[1]],
        ];
        if (pts.length < 3) {
          newRooms.add(room);
          continue;
        }
        final n = pts.length;
        final out = List.generate(n, (i) => [pts[i][0], pts[i][1]]);
        for (var i = 0; i < n; i++) {
          final j = (i + 1) % n;
          final ax = pts[i][0], ay = pts[i][1];
          final bx = pts[j][0], by = pts[j][1];
          final best = _bestMatch(ax, ay, bx, by, normSegs, matchTol);
          if (best == null) continue;
          // 端点吸附到匹配线段端点（按距离选朝向）
          final d1 = _endSum(ax, ay, bx, by, best.x1, best.y1, best.x2, best.y2);
          final d2 = _endSum(ax, ay, bx, by, best.x2, best.y2, best.x1, best.y1);
          if (d1 <= d2) {
            out[i] = [best.x1, best.y1];
            out[j] = [best.x2, best.y2];
          } else {
            out[i] = [best.x2, best.y2];
            out[j] = [best.x1, best.y1];
          }
          snappedEdges++;
        }
        newRooms.add(AiRoom(
          id: room.id,
          name: room.name,
          type: room.type,
          polygon: out,
        ));
      }

      // 开口中心：若靠近某条精校边，则投影到边上（次要）
      final doors = [
        for (final d in input.doors) _snapOpening(d, newRooms, short),
      ];
      final windows = [
        for (final w0 in input.windows) _snapOpeningWin(w0, newRooms, short),
      ];

      final warnings = [
        ...input.warnings,
        if (snappedEdges > 0)
          'ROI 精校：已吸附 $snappedEdges 条房间边到框内线检结果'
        else
          'ROI 精校：检出线段但未达吸附阈值，保留模型坐标',
      ];

      return FloorplanAiResult(
        imageWidth: input.imageWidth,
        imageHeight: input.imageHeight,
        rooms: newRooms,
        walls: input.walls,
        doors: doors,
        windows: windows,
        source: input.source,
        warnings: warnings,
      );
    } catch (e) {
      return _withWarning(input, 'ROI 精校失败，保留模型坐标：$e');
    }
  }

  static FloorplanAiResult _withWarning(FloorplanAiResult r, String w) {
    return FloorplanAiResult(
      imageWidth: r.imageWidth,
      imageHeight: r.imageHeight,
      rooms: r.rooms,
      walls: r.walls,
      doors: r.doors,
      windows: r.windows,
      source: r.source,
      warnings: [...r.warnings, w],
    );
  }

  static List<List<double>> _roomsOuterRoi(List<AiRoom> rooms) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final r in rooms) {
      for (final p in r.polygon) {
        if (p.length < 2) continue;
        minX = math.min(minX, p[0]);
        minY = math.min(minY, p[1]);
        maxX = math.max(maxX, p[0]);
        maxY = math.max(maxY, p[1]);
      }
    }
    return [
      [minX, minY],
      [maxX, minY],
      [maxX, maxY],
      [minX, maxY],
    ];
  }

  static ({double left, double top, double right, double bottom}) _bounding(
    List<List<double>> poly,
  ) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in poly) {
      if (p.length < 2) continue;
      minX = math.min(minX, p[0]);
      minY = math.min(minY, p[1]);
      maxX = math.max(maxX, p[0]);
      maxY = math.max(maxY, p[1]);
    }
    return (left: minX, top: minY, right: maxX, bottom: maxY);
  }

  /// ROI 内正交线段：水平/垂直游程聚合（近似 Hough/LSD 的正交子集）。
  static List<_SegPx> _detectOrthoSegments(img.Image gray) {
    final w = gray.width;
    final h = gray.height;
    // Sobel 近似：边缘掩码
    final edge = List<bool>.filled(w * h, false);
    var sum = 0.0;
    var count = 0;
    final mag = List<double>.filled(w * h, 0);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final gx = _lum(gray, x + 1, y - 1) +
            2 * _lum(gray, x + 1, y) +
            _lum(gray, x + 1, y + 1) -
            _lum(gray, x - 1, y - 1) -
            2 * _lum(gray, x - 1, y) -
            _lum(gray, x - 1, y + 1);
        final gy = _lum(gray, x - 1, y + 1) +
            2 * _lum(gray, x, y + 1) +
            _lum(gray, x + 1, y + 1) -
            _lum(gray, x - 1, y - 1) -
            2 * _lum(gray, x, y - 1) -
            _lum(gray, x + 1, y - 1);
        final m = math.sqrt(gx * gx + gy * gy);
        mag[y * w + x] = m;
        sum += m;
        count++;
      }
    }
    final mean = count == 0 ? 0.0 : sum / count;
    final thr = math.max(28.0, mean * 1.6);
    for (var i = 0; i < mag.length; i++) {
      edge[i] = mag[i] >= thr;
    }

    final segs = <_SegPx>[];
    final minLen = math.max(12, (math.min(w, h) * 0.06).round());

    // 水平游程
    for (var y = 0; y < h; y++) {
      var x = 0;
      while (x < w) {
        while (x < w && !edge[y * w + x]) {
          x++;
        }
        if (x >= w) break;
        final x0 = x;
        while (x < w && edge[y * w + x]) {
          x++;
        }
        if (x - x0 >= minLen) {
          segs.add(_SegPx(x0.toDouble(), y.toDouble(), x.toDouble(), y.toDouble()));
        }
      }
    }
    // 垂直游程
    for (var x = 0; x < w; x++) {
      var y = 0;
      while (y < h) {
        while (y < h && !edge[y * w + x]) {
          y++;
        }
        if (y >= h) break;
        final y0 = y;
        while (y < h && edge[y * w + x]) {
          y++;
        }
        if (y - y0 >= minLen) {
          segs.add(_SegPx(x.toDouble(), y0.toDouble(), x.toDouble(), y.toDouble()));
        }
      }
    }

    // 合并共线近邻，限制数量
    return _mergeSegs(segs, mergeDist: 4).take(120).toList();
  }

  static double _lum(img.Image g, int x, int y) {
    return g.getPixel(x, y).r.toDouble();
  }

  static List<_SegPx> _mergeSegs(
    List<_SegPx> segs, {
    required double mergeDist,
  }) {
    if (segs.isEmpty) return segs;
    final used = List<bool>.filled(segs.length, false);
    final out = <_SegPx>[];
    for (var i = 0; i < segs.length; i++) {
      if (used[i]) continue;
      var cur = segs[i];
      used[i] = true;
      var grew = true;
      while (grew) {
        grew = false;
        for (var j = 0; j < segs.length; j++) {
          if (used[j]) continue;
          final o = segs[j];
          final horiz =
              (cur.y1 - cur.y2).abs() < 1 && (o.y1 - o.y2).abs() < 1;
          final vert =
              (cur.x1 - cur.x2).abs() < 1 && (o.x1 - o.x2).abs() < 1;
          if (horiz && (cur.y1 - o.y1).abs() <= mergeDist) {
            final aMin = math.min(cur.x1, cur.x2);
            final aMax = math.max(cur.x1, cur.x2);
            final bMin = math.min(o.x1, o.x2);
            final bMax = math.max(o.x1, o.x2);
            final sep = aMin > bMax
                ? aMin - bMax
                : (bMin > aMax ? bMin - aMax : 0.0);
            if (sep <= mergeDist * 3) {
              final y = (cur.y1 + o.y1) / 2;
              cur = _SegPx(math.min(aMin, bMin), y, math.max(aMax, bMax), y);
              used[j] = true;
              grew = true;
            }
          } else if (vert && (cur.x1 - o.x1).abs() <= mergeDist) {
            final aMin = math.min(cur.y1, cur.y2);
            final aMax = math.max(cur.y1, cur.y2);
            final bMin = math.min(o.y1, o.y2);
            final bMax = math.max(o.y1, o.y2);
            final sep = aMin > bMax
                ? aMin - bMax
                : (bMin > aMax ? bMin - aMax : 0.0);
            if (sep <= mergeDist * 3) {
              final x = (cur.x1 + o.x1) / 2;
              cur = _SegPx(x, math.min(aMin, bMin), x, math.max(aMax, bMax));
              used[j] = true;
              grew = true;
            }
          }
        }
      }
      out.add(cur);
    }
    out.sort((a, b) => b.len.compareTo(a.len));
    return out;
  }

  static _Seg? _bestMatch(
    double ax,
    double ay,
    double bx,
    double by,
    List<_Seg> segs,
    double tol,
  ) {
    _Seg? best;
    var bestScore = double.infinity;
    final edgeLen = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final isH = (by - ay).abs() <= (bx - ax).abs();
    for (final s in segs) {
      final sH = (s.y2 - s.y1).abs() <= (s.x2 - s.x1).abs();
      if (isH != sH) continue;
      final score = math.min(
        _endSum(ax, ay, bx, by, s.x1, s.y1, s.x2, s.y2),
        _endSum(ax, ay, bx, by, s.x2, s.y2, s.x1, s.y1),
      );
      // 长度相近加分：过短线段跳过
      if (s.len < edgeLen * 0.35) continue;
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    if (best == null || bestScore > tol * 2) return null;
    return best;
  }

  static double _endSum(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
    double dx,
    double dy,
  ) {
    return (ax - cx).abs() +
        (ay - cy).abs() +
        (bx - dx).abs() +
        (by - dy).abs();
  }

  static AiDoor _snapOpening(AiDoor d, List<AiRoom> rooms, double shortPx) {
    final cx = d.cx;
    final cy = d.cy;
    if (cx == null || cy == null) return d;
    final p = _projectToNearestEdge(cx, cy, rooms, 0.02);
    if (p == null) return d;
    return AiDoor(
      id: d.id,
      wallId: d.wallId,
      position: d.position,
      width: d.width,
      cx: p.$1,
      cy: p.$2,
    );
  }

  static AiWindow _snapOpeningWin(
    AiWindow d,
    List<AiRoom> rooms,
    double shortPx,
  ) {
    final cx = d.cx;
    final cy = d.cy;
    if (cx == null || cy == null) return d;
    final p = _projectToNearestEdge(cx, cy, rooms, 0.02);
    if (p == null) return d;
    return AiWindow(
      id: d.id,
      wallId: d.wallId,
      position: d.position,
      width: d.width,
      cx: p.$1,
      cy: p.$2,
    );
  }

  static (double, double)? _projectToNearestEdge(
    double x,
    double y,
    List<AiRoom> rooms,
    double maxDist,
  ) {
    var bestD = maxDist;
    double? px, py;
    for (final r in rooms) {
      final pts = r.polygon;
      final n = pts.length;
      for (var i = 0; i < n; i++) {
        final a = pts[i];
        final b = pts[(i + 1) % n];
        if (a.length < 2 || b.length < 2) continue;
        final proj = _projectPoint(x, y, a[0], a[1], b[0], b[1]);
        final d = math.sqrt(
          (proj.$1 - x) * (proj.$1 - x) + (proj.$2 - y) * (proj.$2 - y),
        );
        if (d < bestD) {
          bestD = d;
          px = proj.$1;
          py = proj.$2;
        }
      }
    }
    if (px == null || py == null) return null;
    return (px, py);
  }

  static (double, double) _projectPoint(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) return (ax, ay);
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (ax + t * dx, ay + t * dy);
  }
}

class _SegPx {
  _SegPx(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
  double get len => math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
}

class _Seg {
  _Seg(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
  double get len => math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
}
