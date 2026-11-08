import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/image_contain.dart';

/// 局部替换：在效果图上粗笔涂抹（归一化 0～1，相对 contain 内容区）。
class InpaintEditor extends StatefulWidget {
  const InpaintEditor({
    super.key,
    required this.imageBytes,
    required this.onChanged,
    this.brushNorm = 0.045,
  });

  final List<int> imageBytes;
  final ValueChanged<List<List<List<double>>>> onChanged;
  final double brushNorm;

  @override
  State<InpaintEditor> createState() => _InpaintEditorState();
}

class _InpaintEditorState extends State<InpaintEditor> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _live;
  Size? _viewport;
  ui.Image? _decoded;
  double _aspect = 4 / 3;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant InpaintEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.imageBytes, widget.imageBytes)) {
      _loadImage();
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(widget.imageBytes),
      );
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _decoded?.dispose();
        _decoded = frame.image;
        _aspect = frame.image.width / frame.image.height;
      });
    } catch (_) {}
  }

  Rect get _contentBox {
    final vp = _viewport;
    if (vp == null) return Rect.zero;
    return containRect(vp, _aspect);
  }

  void _emit() {
    final box = _contentBox;
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
            viewportToNorm(p, box).dx,
            viewportToNorm(p, box).dy,
          ],
      ]);
    }
    widget.onChanged(out);
  }

  void _onStart(DragStartDetails d) {
    final box = _contentBox;
    if (!box.contains(d.localPosition)) return;
    setState(() => _live = [d.localPosition]);
  }

  void _onUpdate(DragUpdateDetails d) {
    final live = _live;
    if (live == null) return;
    final box = _contentBox;
    final p = Offset(
      d.localPosition.dx.clamp(box.left, box.right),
      d.localPosition.dy.clamp(box.top, box.bottom),
    );
    setState(() => live.add(p));
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
    final box = _contentBox;
    final brushPx = box.width < 1
        ? 18.0
        : (box.shortestSide * widget.brushNorm).clamp(8.0, 48.0);

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
                    Image.memory(
                      Uint8List.fromList(widget.imageBytes),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    CustomPaint(
                      painter: _MaskStrokePainter(
                        strokes: _strokes,
                        live: _live,
                        strokeWidth: brushPx,
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
                            '涂抹要改的区域（红区）。圈外尽量保持；弱约束，边缘可能有轻微渗色。',
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

class _MaskStrokePainter extends CustomPainter {
  _MaskStrokePainter({
    required this.strokes,
    required this.live,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final List<Offset>? live;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99E11D48)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void draw(List<Offset> s, Color c) {
      if (s.length < 2) return;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint..color = c);
    }

    for (final s in strokes) {
      draw(s, const Color(0x99E11D48));
    }
    final l = live;
    if (l != null) draw(l, const Color(0xCCE11D48));
  }

  @override
  bool shouldRepaint(covariant _MaskStrokePainter oldDelegate) => true;
}
