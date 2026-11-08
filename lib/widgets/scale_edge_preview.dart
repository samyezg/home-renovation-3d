import 'package:flutter/material.dart';

import '../../services/floorplan_recognize/floorplan_models.dart';
import '../../theme/app_colors.dart';
import '../../utils/image_contain.dart';

/// 期次 V：比例尺图示选边——在户型预览上高亮参照边 + 双向箭头。
class ScaleEdgePreview extends StatelessWidget {
  const ScaleEdgePreview({
    super.key,
    required this.image,
    required this.edges,
    required this.selected,
    required this.onSelect,
    this.imageAspectRatio = 4 / 3,
  });

  final ImageProvider image;
  final List<ScaleEdgeOption> edges;
  final ScaleEdgeOption? selected;
  final ValueChanged<ScaleEdgeOption> onSelect;
  /// 原图宽/高（bake 后），用于 letterbox 反算
  final double imageAspectRatio;

  static const int maxTapTargets = 3;

  @override
  Widget build(BuildContext context) {
    final candidates = edges.take(maxTapTargets).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final box = containRect(constraints.biggest, imageAspectRatio);
            return Stack(
              fit: StackFit.expand,
              children: [
                Image(image: image, fit: BoxFit.contain),
                CustomPaint(
                  painter: _ScaleEdgePainter(
                    selected: selected,
                    candidates: candidates,
                    contentBox: box,
                  ),
                ),
                for (final e in candidates)
                  _edgeHotspot(e, box, selected?.id == e.id),
                Positioned(
                  left: 8,
                  bottom: 8,
                  right: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      child: Text(
                        '图上橙色双向箭头为当前参照边；可点其它淡色边或下方列表切换',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _edgeHotspot(ScaleEdgeOption e, Rect box, bool isSelected) {
    final a = normToViewport(e.ax, e.ay, box);
    final b = normToViewport(e.bx, e.by, box);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return Positioned(
      left: mid.dx - 28,
      top: mid.dy - 28,
      width: 56,
      height: 56,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(e),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? AppColors.brand.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.01),
          ),
        ),
      ),
    );
  }
}

class _ScaleEdgePainter extends CustomPainter {
  _ScaleEdgePainter({
    required this.selected,
    required this.candidates,
    required this.contentBox,
  });

  final ScaleEdgeOption? selected;
  final List<ScaleEdgeOption> candidates;
  final Rect contentBox;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in candidates) {
      final isSel = selected?.id == e.id;
      _drawEdge(
        canvas,
        e,
        color: isSel ? AppColors.brand : AppColors.brand.withValues(alpha: 0.45),
        stroke: isSel ? 4 : 2.5,
        withArrows: isSel,
      );
    }
    final sel = selected;
    if (sel != null && !candidates.any((c) => c.id == sel.id)) {
      _drawEdge(
        canvas,
        sel,
        color: AppColors.brand,
        stroke: 4,
        withArrows: true,
      );
    }
  }

  void _drawEdge(
    Canvas canvas,
    ScaleEdgeOption e, {
    required Color color,
    required double stroke,
    required bool withArrows,
  }) {
    final a = normToViewport(e.ax, e.ay, contentBox);
    final b = normToViewport(e.bx, e.by, contentBox);
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, b, paint);
    if (!withArrows) return;
    _arrow(canvas, b, a, color);
    _arrow(canvas, a, b, color);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final dir = (b - a);
    final len = dir.distance;
    if (len < 1) return;
    final n = Offset(-dir.dy / len, dir.dx / len);
    final tick = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(mid + n * 8, mid - n * 8, tick);
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Color color) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 1) return;
    final u = dir / len;
    final tip = to;
    final back = tip - u * 14;
    final n = Offset(-u.dy, u.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + n.dx * 7, back.dy + n.dy * 7)
      ..lineTo(back.dx - n.dx * 7, back.dy - n.dy * 7)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ScaleEdgePainter oldDelegate) {
    return oldDelegate.selected?.id != selected?.id ||
        oldDelegate.candidates.length != candidates.length ||
        oldDelegate.contentBox != contentBox;
  }
}
