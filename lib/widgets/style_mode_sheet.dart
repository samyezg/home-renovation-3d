import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/style_mode.dart';

/// I8 样式切换面板：档位 + 色调色点
class StyleModeSheet extends StatelessWidget {
  const StyleModeSheet.canvas({
    super.key,
    required this.mode,
    required this.tone,
    required this.onMode,
    required this.onTone,
  })  : kind = _Kind.canvas,
        view3dMode = null,
        onView3dMode = null;

  const StyleModeSheet.view3d({
    super.key,
    required View3dStyleMode this.view3dMode,
    required this.tone,
    required void Function(View3dStyleMode) this.onView3dMode,
    required this.onTone,
  })  : kind = _Kind.view3d,
        mode = null,
        onMode = null;

  final _Kind kind;
  final CanvasStyleMode? mode;
  final View3dStyleMode? view3dMode;
  final StyleTone tone;
  final void Function(CanvasStyleMode)? onMode;
  final void Function(View3dStyleMode)? onView3dMode;
  final void Function(StyleTone) onTone;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind == _Kind.canvas ? '画布样式' : '3D 样式',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              kind == _Kind.canvas
                  ? '线框 / 简朴 / 手绘草稿（2D 无拟真档）'
                  : '线框 / 卡通 / 轻拟真（过载自动降级卡通）',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (kind == _Kind.canvas)
                  for (final m in CanvasStyleMode.values)
                    ChoiceChip(
                      label: Text(StyleModeCatalog.canvasLabel(m)),
                      selected: mode == m,
                      onSelected: (_) => onMode!(m),
                    )
                else
                  for (final m in View3dStyleMode.values)
                    ChoiceChip(
                      label: Text(StyleModeCatalog.view3dLabel(m)),
                      selected: view3dMode == m,
                      onSelected: (_) => onView3dMode!(m),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('色调预设', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final t in StyleTone.values) ...[
                  _ToneDot(
                    tone: t,
                    selected: tone == t,
                    onTap: () => onTone(t),
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { canvas, view3d }

class _ToneDot extends StatelessWidget {
  const _ToneDot({
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final StyleTone tone;
  final bool selected;
  final VoidCallback onTap;

  Color get _color => switch (tone) {
        StyleTone.warmWood => const Color(0xFFA67C52),
        StyleTone.cream => const Color(0xFFEDE4D4),
        StyleTone.dark => const Color(0xFF3D3428),
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
                width: selected ? 3 : 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            StyleModeCatalog.toneLabel(tone),
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
