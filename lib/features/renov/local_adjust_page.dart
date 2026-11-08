import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../data/renov_styles.dart';
import '../../services/renov/renov_mask.dart';
import '../../services/renov/renov_service.dart';
import '../../services/renov/renov_structure.dart';
import '../../theme/app_colors.dart';
import '../../widgets/inpaint_editor.dart';

/// P1.x：在效果图上涂抹区域 → 局部重绘（弱约束 + mask 合成）。
class LocalAdjustPage extends StatefulWidget {
  const LocalAdjustPage({
    super.key,
    required this.baseBytes,
    required this.style,
    this.structure,
    this.intensity = 'medium',
  });

  final Uint8List baseBytes;
  final RenovStyle style;
  final RenovStructure? structure;
  final String intensity;

  @override
  State<LocalAdjustPage> createState() => _LocalAdjustPageState();
}

class _LocalAdjustPageState extends State<LocalAdjustPage> {
  final _svc = RenovService();
  final _hintCtrl = TextEditingController();
  List<List<List<double>>> _strokes = [];
  double _brushNorm = 0.045;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _hintCtrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_strokes.isEmpty) {
      setState(() => _error = '请先涂抹要替换的区域');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final decoded = img.decodeImage(widget.baseBytes);
      if (decoded == null) throw Exception('无法解码效果图');
      final w = decoded.width;
      final h = decoded.height;
      final mask = RenovMask.bakePng(
        width: w,
        height: h,
        strokes: _strokes,
        brushNorm: _brushNorm,
      );
      if (!RenovMask.hasCoverage(mask)) {
        throw Exception('涂抹区域过小，请多涂几笔');
      }
      final r = await _svc.inpaintLocal(
        baseBytes: widget.baseBytes,
        maskPng: mask,
        style: widget.style,
        structure: widget.structure,
        intensity: widget.intensity,
        userHint: _hintCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('局部替换')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '涂抹要改的区域，可写一句想换成什么。弱约束：圈外由本地 mask 合成强制保留；'
            '圈内依赖模型，非专用 inpaint 服务。',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text('笔刷粗细', style: Theme.of(context).textTheme.titleSmall),
          Slider(
            value: _brushNorm,
            min: 0.02,
            max: 0.09,
            divisions: 7,
            label: _brushNorm < 0.035
                ? '细'
                : _brushNorm > 0.06
                    ? '粗'
                    : '中',
            onChanged: _busy
                ? null
                : (v) => setState(() => _brushNorm = v),
          ),
          InpaintEditor(
            imageBytes: widget.baseBytes,
            brushNorm: _brushNorm,
            onChanged: (s) => setState(() => _strokes = s),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hintCtrl,
            enabled: !_busy,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '想改成什么（可选）',
              hintText: '例如：换成米色布艺沙发 / 墙面改木饰面',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_outlined),
            label: Text(_busy ? '正在局部重绘…' : '生成局部替换'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
