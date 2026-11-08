import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme/app_colors.dart';

/// P1 结构锚点：在实景图上描墙线 / 墙地交界（多段折线，归一化 0～1）。
class StructureAnchorEditor extends StatefulWidget {
  const StructureAnchorEditor({
    super.key,
    required this.image,
    required this.onChanged,
    this.initialStrokes,
  });

  final ImageProvider image;
  final ValueChanged<List<List<List<double>>>> onChanged;
  final List<List<List<double>>>? initialStrokes;

  @override
  State<StructureAnchorEditor> createState() => _StructureAnchorEditorState();
}

class _StructureAnchorEditorState extends State<StructureAnchorEditor> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _live;
  Size? _viewport;

  @override
  void initState() {
    super.initState();
    final init = widget.initialStrokes;
    if (init != null && init.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _viewport == null) return;
        final box = Offset.zero & _viewport!;
        setState(() {
          for (final s in init) {
            _strokes.add([
              for (final p in s)
                if (p.length >= 2)
                  Offset(
                    box.left + p[0].clamp(0.0, 1.0) * box.width,
                    box.top + p[1].clamp(0.0, 1.0) * box.height,
                  ),
            ]);
          }
        });
        _emit();
      });
    }
  }

  void _emit() {
    final vp = _viewport;
    if (vp == null) {
      widget.onChanged(const []);
      return;
    }
    final box = Offset.zero & vp;
    if (box.width < 1 || box.height < 1) {
      widget.onChanged(const []);
      return;
    }
    final out = <List<List<double>>>[];
    for (final s in _strokes) {
      if (s.length < 2) continue;
      out.add([
        for (final p in s)
          [
            ((p.dx - box.left) / box.width).clamp(0.0, 1.0),
            ((p.dy - box.top) / box.height).clamp(0.0, 1.0),
          ],
      ]);
    }
    widget.onChanged(out);
  }

  void _onStart(DragStartDetails d) {
    setState(() => _live = [d.localPosition]);
  }

  void _onUpdate(DragUpdateDetails d) {
    final live = _live;
    if (live == null) return;
    setState(() => live.add(d.localPosition));
  }

  void _onEnd(DragEndDetails d) {
    final live = _live;
    if (live == null || live.length < 2) {
      setState(() => _live = null);
      return;
    }
    setState(() {
      _strokes.add(List<Offset>.from(live));
      _live = null;
    });
    _emit();
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
    _emit();
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _live = null;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(onPressed: _undo, child: const Text('撤销一笔')),
            TextButton(onPressed: _clear, child: const Text('清除')),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: LayoutBuilder(
              builder: (context, c) {
                _viewport = c.biggest;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(image: widget.image, fit: BoxFit.contain),
                    CustomPaint(
                      painter: _AnchorPainter(
                        strokes: _strokes,
                        live: _live,
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onStart,
                      onPanUpdate: _onUpdate,
                      onPanEnd: _onEnd,
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
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            '沿墙角、墙地交界轻轻描线（可选）。锚点优先锁定门窗与边界，减少改完变形。',
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
        ),
      ],
    );
  }
}

class _AnchorPainter extends CustomPainter {
  _AnchorPainter({required this.strokes, required this.live});

  final List<List<Offset>> strokes;
  final List<Offset>? live;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brand
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final l = live;
    if (l != null && l.length >= 2) {
      final path = Path()..moveTo(l.first.dx, l.first.dy);
      for (var i = 1; i < l.length; i++) {
        path.lineTo(l[i].dx, l[i].dy);
      }
      canvas.drawPath(
        path,
        paint..color = AppColors.brand.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnchorPainter oldDelegate) => true;
}

/// 弱控制：从实景图提取少量长边缘折线，写入 prompt（非 ControlNet）。
abstract final class AutoEdgeHints {
  static Future<List<List<List<double>>>> extract(
    List<int> imageBytes, {
    int maxStrokes = 8,
  }) async {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
      if (decoded == null) return const [];
      // 缩小平铺加速
      final small = img.copyResize(
        decoded,
        width: math.min(480, decoded.width),
      );
      final gray = img.grayscale(small);
      final w = gray.width;
      final h = gray.height;
      final mag = List<double>.filled(w * h, 0);
      var sum = 0.0;
      var n = 0;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final gx = _l(gray, x + 1, y) - _l(gray, x - 1, y);
          final gy = _l(gray, x, y + 1) - _l(gray, x, y - 1);
          final m = math.sqrt(gx * gx + gy * gy);
          mag[y * w + x] = m;
          sum += m;
          n++;
        }
      }
      final thr = math.max(40.0, (n == 0 ? 0 : sum / n) * 2.2);
      final strokes = <List<List<double>>>[];
      // 水平长边采样
      for (var y = h ~/ 5; y < h * 4 ~/ 5; y += h ~/ 12) {
        final pts = <List<double>>[];
        for (var x = 2; x < w - 2; x++) {
          if (mag[y * w + x] >= thr) {
            pts.add([x / w, y / h]);
          }
        }
        if (pts.length >= 8) {
          strokes.add([pts.first, pts[pts.length ~/ 2], pts.last]);
        }
        if (strokes.length >= maxStrokes) break;
      }
      // 垂直
      for (var x = w ~/ 5; x < w * 4 ~/ 5 && strokes.length < maxStrokes; x += w ~/ 10) {
        final pts = <List<double>>[];
        for (var y = 2; y < h - 2; y++) {
          if (mag[y * w + x] >= thr) {
            pts.add([x / w, y / h]);
          }
        }
        if (pts.length >= 8) {
          strokes.add([pts.first, pts[pts.length ~/ 2], pts.last]);
        }
      }
      return strokes.take(maxStrokes).toList();
    } catch (_) {
      return const [];
    }
  }

  static double _l(img.Image g, int x, int y) => g.getPixel(x, y).r.toDouble();
}

/// 将描线叠到缩略图（可选，供 debug / 本地预览）。
Future<Uint8List?> bakeAnchorsPreview(
  List<int> imageBytes,
  List<List<List<double>>> strokes,
) async {
  try {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(imageBytes),
    );
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width;
    final h = src.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(src, Offset.zero, Paint());
    final paint = Paint()
      ..color = const Color(0xE0C45C26)
      ..strokeWidth = math.max(2.0, w / 400)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()
        ..moveTo(s.first[0] * w, s.first[1] * h);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i][0] * w, s[i][1] * h);
      }
      canvas.drawPath(path, paint);
    }
    final pic = recorder.endRecording();
    final out = await pic.toImage(w, h);
    final bd = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
