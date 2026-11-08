/// I21 P1：改造风格库（V1 主流 8 种；无依赖外链素材）。
class RenovStyle {
  const RenovStyle({
    required this.id,
    required this.name,
    required this.blurb,
    required this.promptHint,
    required this.swatch,
  });

  final String id;
  final String name;
  final String blurb;
  /// 写入生成 prompt 的风格描述（中英混合利于多模态）
  final String promptHint;
  /// 卡片色块 ARGB
  final int swatch;
}

abstract final class RenovStyles {
  static const all = <RenovStyle>[
    RenovStyle(
      id: 'modern_simple',
      name: '现代简约',
      blurb: '黑白灰+原木，线条干净',
      promptHint:
          'modern minimalist interior, clean lines, neutral gray white oak, uncluttered',
      swatch: 0xFF6B7280,
    ),
    RenovStyle(
      id: 'nordic',
      name: '北欧风',
      blurb: '白+浅木+绿植，明亮温馨',
      promptHint:
          'Scandinavian nordic interior, bright white, light wood, plants, cozy',
      swatch: 0xFF93C5FD,
    ),
    RenovStyle(
      id: 'cream',
      name: '奶油风',
      blurb: '米白奶咖，柔和治愈',
      promptHint:
          'cream style interior, beige ivory soft curves, warm cozy lighting',
      swatch: 0xFFE8D5C4,
    ),
    RenovStyle(
      id: 'wabi',
      name: '侘寂风',
      blurb: '微水泥+原木，极简禅意',
      promptHint:
          'wabi-sabi interior, microcement plaster, raw wood, zen minimal',
      swatch: 0xFFA8A29E,
    ),
    RenovStyle(
      id: 'japandi',
      name: '日式原木',
      blurb: '原木+白，自然清新',
      promptHint:
          'Japanese wood interior, natural oak, white walls, tatami mood, calm',
      swatch: 0xFFD6B98C,
    ),
    RenovStyle(
      id: 'light_luxury',
      name: '轻奢风',
      blurb: '金属+石材，精致高级',
      promptHint:
          'light luxury interior, marble accents, brushed metal, elegant dark tones',
      swatch: 0xFFC4B5A0,
    ),
    RenovStyle(
      id: 'new_chinese',
      name: '新中式',
      blurb: '实木+禅意，传统现结合',
      promptHint:
          'new Chinese style interior, dark wood, ink landscape accents, modern oriental',
      swatch: 0xFF8B4513,
    ),
    RenovStyle(
      id: 'industrial',
      name: '工业风',
      blurb: '水泥+金属，个性酷感',
      promptHint:
          'industrial loft interior, concrete, black metal, exposed texture',
      swatch: 0xFF57534E,
    ),
  ];

  static RenovStyle byId(String id) =>
      all.firstWhere((e) => e.id == id, orElse: () => all.first);
}
