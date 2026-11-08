import 'package:flutter/material.dart';

import 'app_colors.dart';

/// I8 · 画布 / 3D 显示模式（统一概念，分端实现）
enum CanvasStyleMode {
  /// 线框：墙线 + 透明房间
  wireframe,

  /// 简朴：现状彩色块（默认）
  simple,

  /// 手绘草稿：纸张底 + 笔触描边
  sketch,
}

enum View3dStyleMode {
  /// 线框轮廓
  wireframe,

  /// 卡通风（候选默认）
  cartoon,

  /// 轻拟真（环境感 + 阴影；过载降级卡通）
  softReal,
}

/// 色调预设（V1 只改配色参数）
enum StyleTone {
  warmWood,
  cream,
  dark,
}

abstract final class StyleModeCatalog {
  static const canvasModes = CanvasStyleMode.values;
  static const view3dModes = View3dStyleMode.values;
  static const tones = StyleTone.values;

  static String canvasLabel(CanvasStyleMode m) => switch (m) {
        CanvasStyleMode.wireframe => '线框',
        CanvasStyleMode.simple => '简朴',
        CanvasStyleMode.sketch => '手绘草稿',
      };

  static String view3dLabel(View3dStyleMode m) => switch (m) {
        View3dStyleMode.wireframe => '线框',
        View3dStyleMode.cartoon => '卡通',
        View3dStyleMode.softReal => '轻拟真',
      };

  static String toneLabel(StyleTone t) => switch (t) {
        StyleTone.warmWood => '暖木',
        StyleTone.cream => '奶油白',
        StyleTone.dark => '深色',
      };

  static CanvasStyleMode parseCanvas(String? raw) {
    for (final m in CanvasStyleMode.values) {
      if (m.name == raw) return m;
    }
    return CanvasStyleMode.simple;
  }

  static View3dStyleMode parseView3d(String? raw) {
    for (final m in View3dStyleMode.values) {
      if (m.name == raw) return m;
    }
    return View3dStyleMode.cartoon;
  }

  static StyleTone parseTone(String? raw) {
    for (final t in StyleTone.values) {
      if (t.name == raw) return t;
    }
    return StyleTone.warmWood;
  }

  /// 画布配色
  static CanvasPalette canvasPalette(CanvasStyleMode mode, StyleTone tone) {
    final base = switch (tone) {
      StyleTone.warmWood => (
          bg: const Color(0xFFF4F3F0),
          paper: const Color(0xFFF7F1E6),
          fill: AppColors.brandSoft,
          wall: AppColors.brand,
          accent: AppColors.accent,
          ink: const Color(0xFF3D3428),
        ),
      StyleTone.cream => (
          bg: const Color(0xFFFAF8F4),
          paper: const Color(0xFFFFFCF7),
          fill: const Color(0xFFEDE4D4),
          wall: const Color(0xFF8A7A68),
          accent: const Color(0xFF6B8F71),
          ink: const Color(0xFF4A433A),
        ),
      StyleTone.dark => (
          bg: const Color(0xFF1C1A18),
          paper: const Color(0xFF2A2622),
          fill: const Color(0xFF3D3428),
          wall: const Color(0xFFC4A574),
          accent: const Color(0xFF7FA08A),
          ink: const Color(0xFFE8E0D4),
        ),
    };
    return CanvasPalette(
      background: mode == CanvasStyleMode.sketch ? base.paper : base.bg,
      roomFill: mode == CanvasStyleMode.wireframe
          ? Colors.transparent
          : base.fill.withValues(alpha: mode == CanvasStyleMode.sketch ? 0.55 : 0.92),
      roomBorder: mode == CanvasStyleMode.sketch ? base.ink : base.wall,
      wallStroke: mode == CanvasStyleMode.wireframe ? base.ink : base.wall,
      selectedBorder: base.accent,
      grid: tone == StyleTone.dark
          ? const Color(0xFF3A3530)
          : AppColors.border,
      text: mode == CanvasStyleMode.sketch ? base.ink : AppColors.textPrimary,
      strokeWidth: mode == CanvasStyleMode.sketch ? 2.8 : (mode == CanvasStyleMode.wireframe ? 1.8 : 1.5),
      sketchy: mode == CanvasStyleMode.sketch,
      showRoomFill: mode != CanvasStyleMode.wireframe,
    );
  }

  /// 3D 主题色（传给 WebView）
  static Map<String, dynamic> view3dThemePayload(
    View3dStyleMode mode,
    StyleTone tone,
  ) {
    final colors = switch (tone) {
      StyleTone.warmWood => {
          'bg': '#F4F3F0',
          'brand': '#A67C52',
          'floor': '#E8E4DC',
          'wall': '#F7F4EF',
          'cabinet': '#A67C52',
          'furniture': '#4F6F5A',
        },
      StyleTone.cream => {
          'bg': '#FAF8F4',
          'brand': '#8A7A68',
          'floor': '#F0EBE0',
          'wall': '#FFFCF7',
          'cabinet': '#C4B09A',
          'furniture': '#6B8F71',
        },
      StyleTone.dark => {
          'bg': '#161513',
          'brand': '#C4A574',
          'floor': '#2A2622',
          'wall': '#3D3428',
          'cabinet': '#C4A574',
          'furniture': '#7FA08A',
        },
    };
    return {
      ...colors,
      'style_mode': mode.name,
      'tone': tone.name,
    };
  }
}

class CanvasPalette {
  const CanvasPalette({
    required this.background,
    required this.roomFill,
    required this.roomBorder,
    required this.wallStroke,
    required this.selectedBorder,
    required this.grid,
    required this.text,
    required this.strokeWidth,
    required this.sketchy,
    required this.showRoomFill,
  });

  final Color background;
  final Color roomFill;
  final Color roomBorder;
  final Color wallStroke;
  final Color selectedBorder;
  final Color grid;
  final Color text;
  final double strokeWidth;
  final bool sketchy;
  final bool showRoomFill;
}
