import 'package:flutter/material.dart';

/// 前后对比滑块：左原图 / 右效果图。
class BeforeAfterSlider extends StatefulWidget {
  const BeforeAfterSlider({
    super.key,
    required this.before,
    required this.after,
  });

  final ImageProvider before;
  final ImageProvider after;

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  double _t = 0.5;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final split = (w * _t).clamp(8.0, w - 8);
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(image: widget.after, fit: BoxFit.cover),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _t.clamp(0.02, 0.98),
                    child: SizedBox(
                      width: w,
                      height: c.maxHeight,
                      child: Image(image: widget.before, fit: BoxFit.cover),
                    ),
                  ),
                ),
                Positioned(
                  left: split - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white),
                ),
                Positioned(
                  left: split - 18,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.drag_handle, size: 18),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: _tag('改造前'),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: _tag('改造后'),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        _t = (_t + d.delta.dx / w).clamp(0.05, 0.95);
                      });
                    },
                    onTapDown: (d) {
                      setState(() {
                        _t = (d.localPosition.dx / w).clamp(0.05, 0.95);
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tag(String t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          t,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }
}
