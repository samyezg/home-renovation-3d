import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/image_contain.dart';

export '../services/floorplan_recognize/roi_geom.dart';

/// 期次 AA：在户型图上框选 / 描外轮廓（归一化 0～1，相对原图）。
class FloorplanRoiEditor extends StatefulWidget {
  const FloorplanRoiEditor({
    super.key,
    required this.image,
    required this.onChanged,
    this.initialPolygon,
    this.imageAspectRatio = 4 / 3,
  });

  final ImageProvider image;
  final ValueChanged<List<List<double>>?> onChanged;
  final List<List<double>>? initialPolygon;
  final double imageAspectRatio;

  @override
  State<FloorplanRoiEditor> createState() => _FloorplanRoiEditorState();
}

class _FloorplanRoiEditorState extends State<FloorplanRoiEditor> {
  var _mode = _RoiMode.rect;
  Offset? _rectStart;
  Offset? _rectEnd;
  final List<Offset> _stroke = [];
  List<Offset>? _polygon;
  Size? _viewport;

  Rect get _contentBox {
    final vp = _viewport;
    if (vp == null) return Rect.zero;
    return containRect(vp, widget.imageAspectRatio);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialPolygon != null && widget.initialPolygon!.length >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _viewport == null) return;
        final box = _contentBox;
        setState(() {
          _polygon = [
            for (final p in widget.initialPolygon!)
              normToViewport(p[0], p[1], box),
          ];
        });
        _emit();
      });
    }
  }

  void _emit() {
    final poly = _polygon;
    if (poly == null || poly.length < 3 || _viewport == null) {
      widget.onChanged(null);
      return;
    }
    final box = _contentBox;
    if (box.width < 1 || box.height < 1) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged([
      for (final p in poly)
        [
          viewportToNorm(p, box).dx,
          viewportToNorm(p, box).dy,
        ],
    ]);
  }

  void _onPanStart(DragStartDetails d) {
    final local = d.localPosition;
    if (_mode == _RoiMode.rect) {
      setState(() {
        _rectStart = local;
        _rectEnd = local;
        _polygon = null;
        _stroke.clear();
      });
    } else {
      setState(() {
        _stroke
          ..clear()
          ..add(local);
        _polygon = null;
        _rectStart = null;
        _rectEnd = null;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final local = d.localPosition;
    if (_mode == _RoiMode.rect) {
      setState(() => _rectEnd = local);
    } else {
      setState(() => _stroke.add(local));
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_mode == _RoiMode.rect) {
      final a = _rectStart;
      final b = _rectEnd;
      if (a == null || b == null) return;
      final left = math.min(a.dx, b.dx);
      final right = math.max(a.dx, b.dx);
      final top = math.min(a.dy, b.dy);
      final bottom = math.max(a.dy, b.dy);
      if ((right - left) < 24 || (bottom - top) < 24) {
        setState(() {
          _rectStart = null;
          _rectEnd = null;
          _polygon = null;
        });
        widget.onChanged(null);
        return;
      }
      setState(() {
        _polygon = [
          Offset(left, top),
          Offset(right, top),
          Offset(right, bottom),
          Offset(left, bottom),
        ];
        _rectStart = null;
        _rectEnd = null;
      });
      _emit();
      return;
    }
    if (_stroke.length < 4) {
      setState(() {
        _stroke.clear();
        _polygon = null;
      });
      widget.onChanged(null);
      return;
    }
    final simplified = _simplifyStroke(_stroke);
    setState(() {
      _polygon = simplified;
      _stroke.clear();
    });
    _emit();
  }

  void _clear() {
    setState(() {
      _polygon = null;
      _stroke.clear();
      _rectStart = null;
      _rectEnd = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ChoiceChip(
              label: const Text('框选'),
              selected: _mode == _RoiMode.rect,
              onSelected: (_) => setState(() => _mode = _RoiMode.rect),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('描外轮廓'),
              selected: _mode == _RoiMode.freehand,
              onSelected: (_) => setState(() => _mode = _RoiMode.freehand),
            ),
            const Spacer(),
            TextButton(onPressed: _clear, child: const Text('清除')),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(image: widget.image, fit: BoxFit.contain),
                    CustomPaint(
                      painter: _RoiPainter(
                        polygon: _polygon,
                        stroke: _stroke,
                        rectStart: _rectStart,
                        rectEnd: _rectEnd,
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      right: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            _mode == _RoiMode.rect
                                ? '拖出矩形框住整套户型（框外忽略）'
                                : '沿外墙描一圈，松手后自动闭合',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static List<Offset> _simplifyStroke(List<Offset> stroke) {
    if (stroke.isEmpty) return const [];
    const sampleStep = 12.0;
    final sampled = <Offset>[stroke.first];
    var acc = 0.0;
    for (var i = 1; i < stroke.length; i++) {
      acc += (stroke[i] - stroke[i - 1]).distance;
      if (acc >= sampleStep) {
        sampled.add(stroke[i]);
        acc = 0;
      }
    }
    if ((sampled.last - stroke.last).distance > 4) {
      sampled.add(stroke.last);
    }
    if ((sampled.first - sampled.last).distance > 20) {
      sampled.add(sampled.first);
    }
    var simplified = _douglasPeucker(sampled, 10);
    if (simplified.length >= 2 &&
        (simplified.first - simplified.last).distance < 1) {
      simplified = simplified.sublist(0, simplified.length - 1);
    }
    final dedup = <Offset>[];
    for (final p in simplified) {
      if (dedup.isEmpty || (dedup.last - p).distance >= 6) {
        dedup.add(p);
      }
    }
    if (dedup.length < 3) {
      double minX = stroke.first.dx, maxX = stroke.first.dx;
      double minY = stroke.first.dy, maxY = stroke.first.dy;
      for (final p in stroke) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      return [
        Offset(minX, minY),
        Offset(maxX, minY),
        Offset(maxX, maxY),
        Offset(minX, maxY),
      ];
    }
    return dedup;
  }

  static List<Offset> _douglasPeucker(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return List<Offset>.from(pts);
    var maxDist = 0.0;
    var idx = 0;
    final a = pts.first;
    final b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _perpDist(pts[i], a, b);
      if (d > maxDist) {
        maxDist = d;
        idx = i;
      }
    }
    if (maxDist > epsilon) {
      final left = _douglasPeucker(pts.sublist(0, idx + 1), epsilon);
      final right = _douglasPeucker(pts.sublist(idx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _perpDist(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-9) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }
}

enum _RoiMode { rect, freehand }

class _RoiPainter extends CustomPainter {
  _RoiPainter({
    required this.polygon,
    required this.stroke,
    required this.rectStart,
    required this.rectEnd,
  });

  final List<Offset>? polygon;
  final List<Offset> stroke;
  final Offset? rectStart;
  final Offset? rectEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = AppColors.brand.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = AppColors.brand
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final poly = polygon;
    if (poly != null && poly.length >= 3) {
      final outer = Path()..addRect(Offset.zero & size);
      final inner = Path()..addPolygon(poly, true);
      canvas.drawPath(
        Path.combine(PathOperation.difference, outer, inner),
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawPath(inner, fill);
      canvas.drawPath(inner, strokePaint);
      return;
    }

    if (rectStart != null && rectEnd != null) {
      final r = Rect.fromPoints(rectStart!, rectEnd!);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, strokePaint);
      return;
    }

    if (stroke.length >= 2) {
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoiPainter oldDelegate) {
    return oldDelegate.polygon != polygon ||
        oldDelegate.stroke.length != stroke.length ||
        oldDelegate.rectStart != rectStart ||
        oldDelegate.rectEnd != rectEnd;
  }
}
