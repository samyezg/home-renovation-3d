import 'package:flutter/material.dart';

import '../data/catalogs.dart';
import '../models/plan.dart';
import '../theme/app_colors.dart';

/// 户型缩略图：高区分色 + 房间首字；可选门/窗示意点。
class PlanThumb extends StatelessWidget {
  const PlanThumb({
    super.key,
    required this.plan,
    this.width = 50,
    this.height = 40,
    this.showLabels = true,
    this.showOpenings = true,
  });

  final PlanDocument plan;
  final double width;
  final double height;
  final bool showLabels;
  final bool showOpenings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: CustomPaint(
            painter: _PlanThumbPainter(
              plan,
              showLabels: showLabels,
              showOpenings: showOpenings,
            ),
            size: Size(width, height),
          ),
        ),
      ),
    );
  }
}

class _PlanThumbPainter extends CustomPainter {
  _PlanThumbPainter(
    this.plan, {
    required this.showLabels,
    required this.showOpenings,
  });

  final PlanDocument plan;
  final bool showLabels;
  final bool showOpenings;

  /// 色相拉开，避免客厅/厨房发灰难辨。
  static Color _colorFor(String type) => switch (type) {
        'living' => const Color(0xFFE8B86D),
        'dining' => const Color(0xFFF0C27A),
        'kitchen' => const Color(0xFFE07A5F),
        'bedroom_master' => const Color(0xFF6BAF8D),
        'bedroom' => const Color(0xFF8FBF9A),
        'bathroom' || 'bath' => const Color(0xFF5B9BB8),
        'balcony' => const Color(0xFFA8C97A),
        'study' => const Color(0xFF6B9E9E),
        'entry' => const Color(0xFFC4B5A5),
        _ => const Color(0xFFD0CBC3),
      };

  static String _glyph(RoomRect r) {
    final n = r.name.trim();
    if (n.isNotEmpty) return String.fromCharCodes(n.runes.take(1));
    final label = RoomTypeLabels.labels[r.type] ?? '房';
    return String.fromCharCodes(label.runes.take(1));
  }

  static double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    return Offset(dx, dy).distance;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rooms = plan.rooms;
    if (rooms.isEmpty) {
      final p = Paint()..color = AppColors.border.withValues(alpha: 0.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
          const Radius.circular(3),
        ),
        p,
      );
      return;
    }

    double minX = rooms.first.x;
    double minY = rooms.first.y;
    double maxX = rooms.first.x + rooms.first.widthCm;
    double maxY = rooms.first.y + rooms.first.depthCm;
    for (final r in rooms) {
      minX = minX < r.x ? minX : r.x;
      minY = minY < r.y ? minY : r.y;
      maxX = maxX > r.x + r.widthCm ? maxX : r.x + r.widthCm;
      maxY = maxY > r.y + r.depthCm ? maxY : r.y + r.depthCm;
    }

    final pad = 3.0;
    final bw = maxX - minX;
    final bh = maxY - minY;
    if (bw <= 0 || bh <= 0) return;
    final scaleW = (size.width - pad * 2) / bw;
    final scaleH = (size.height - pad * 2) / bh;
    final scale = scaleW < scaleH ? scaleW : scaleH;

    final ox = (size.width - bw * scale) / 2;
    final oy = (size.height - bh * scale) / 2;

    Offset map(double x, double y) =>
        Offset(ox + (x - minX) * scale, oy + (y - minY) * scale);

    for (final r in rooms) {
      final color = _colorFor(r.type);
      final stroke = Paint()
        ..color = const Color(0xFF5A5248)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7;
      late Rect bounds;
      if (r.hasPolygon) {
        final path = Path();
        final pts = r.polygon!;
        final first = map(pts.first[0], pts.first[1]);
        path.moveTo(first.dx, first.dy);
        for (var i = 1; i < pts.length; i++) {
          final p = map(pts[i][0], pts[i][1]);
          path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, Paint()..color = color);
        canvas.drawPath(path, stroke);
        bounds = path.getBounds();
      } else {
        bounds = Rect.fromLTWH(
          map(r.x, r.y).dx,
          map(r.x, r.y).dy,
          r.widthCm * scale,
          r.depthCm * scale,
        );
        canvas.drawRect(bounds, Paint()..color = color);
        canvas.drawRect(bounds, stroke);
      }

      if (showLabels && bounds.width >= 10 && bounds.height >= 10) {
        final tp = TextPainter(
          text: TextSpan(
            text: _glyph(r),
            style: TextStyle(
              color: const Color(0xFF3D3832).withValues(alpha: 0.85),
              fontSize: (bounds.shortestSide * 0.42).clamp(7.0, 12.0),
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: bounds.width);
        tp.paint(
          canvas,
          Offset(
            bounds.center.dx - tp.width / 2,
            bounds.center.dy - tp.height / 2,
          ),
        );
      }
    }

    if (showOpenings) {
      final doorPaint = Paint()..color = const Color(0xFF2F2A26);
      final winPaint = Paint()..color = const Color(0xFF3D7EA6);
      for (final d in plan.doors) {
        final wallId = d.wallId;
        if (wallId == null) continue;
        WallSeg? wall;
        for (final w in plan.walls) {
          if (w.id == wallId) {
            wall = w;
            break;
          }
        }
        if (wall == null) continue;
        final len = _wallLen(wall);
        final t = (d.centerCm / (len <= 0 ? 1 : len)).clamp(0.0, 1.0);
        final p = map(
          wall.x1 + (wall.x2 - wall.x1) * t,
          wall.y1 + (wall.y2 - wall.y1) * t,
        );
        canvas.drawCircle(p, 1.6, doorPaint);
      }
      for (final win in plan.windows) {
        final wallId = win.wallId;
        if (wallId == null) continue;
        WallSeg? wall;
        for (final w in plan.walls) {
          if (w.id == wallId) {
            wall = w;
            break;
          }
        }
        if (wall == null) continue;
        final len = _wallLen(wall);
        final t = (win.centerCm / (len <= 0 ? 1 : len)).clamp(0.0, 1.0);
        final p = map(
          wall.x1 + (wall.x2 - wall.x1) * t,
          wall.y1 + (wall.y2 - wall.y1) * t,
        );
        canvas.drawCircle(p, 1.4, winPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PlanThumbPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.showLabels != showLabels ||
      oldDelegate.showOpenings != showOpenings;
}
