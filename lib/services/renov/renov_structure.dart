import 'dart:convert';

/// P1 B 路径：实景结构理解中间结果（可回流 3D / 写入生成 prompt）。
///
/// Schema（简化版，与 `understandStructure` prompt 对齐）：
/// ```json
/// {
///   "room_type": "living_room|bedroom|…",
///   "summary": "…",
///   "walls|doors|windows|furniture": [{"name","cx","cy","desc"}],
///   "keep": ["…"]
/// }
/// ```
/// `cx`/`cy` 为相对整图 0～1（左上原点）的**中心点**，非轮廓 polygon / 无 w·h / 无朝向。
/// 喂给生成时为**纯文本**（`toPromptBlock`），非画进图。结构保留仅到「大概在此位置有此要素」级别。
class RenovStructure {
  RenovStructure({
    this.roomType = 'other',
    this.summary = '',
    this.walls = const [],
    this.doors = const [],
    this.windows = const [],
    this.furniture = const [],
    this.keepHints = const [],
    this.raw = const {},
  });

  final String roomType;
  final String summary;
  final List<RenovStructItem> walls;
  final List<RenovStructItem> doors;
  final List<RenovStructItem> windows;
  final List<RenovStructItem> furniture;
  final List<String> keepHints;
  /// 原始 JSON，供后续 hook / 导出
  final Map<String, dynamic> raw;

  bool get isEmpty =>
      walls.isEmpty &&
      doors.isEmpty &&
      windows.isEmpty &&
      furniture.isEmpty &&
      summary.trim().isEmpty;

  factory RenovStructure.fromJson(Map<String, dynamic> j) {
    List<RenovStructItem> list(String key) => (j[key] as List? ?? [])
        .whereType<Map>()
        .map((e) => RenovStructItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return RenovStructure(
      roomType: '${j['room_type'] ?? j['roomType'] ?? 'other'}',
      summary: '${j['summary'] ?? ''}',
      walls: list('walls'),
      doors: list('doors'),
      windows: list('windows'),
      furniture: list('furniture'),
      keepHints: (j['keep'] as List?)?.map((e) => '$e').toList() ??
          (j['keep_hints'] as List?)?.map((e) => '$e').toList() ??
          const [],
      raw: Map<String, dynamic>.from(j),
    );
  }

  Map<String, dynamic> toJson() => raw.isNotEmpty
      ? raw
      : {
          'room_type': roomType,
          'summary': summary,
          'walls': walls.map((e) => e.toJson()).toList(),
          'doors': doors.map((e) => e.toJson()).toList(),
          'windows': windows.map((e) => e.toJson()).toList(),
          'furniture': furniture.map((e) => e.toJson()).toList(),
          'keep': keepHints,
        };

  /// 写入生成 prompt 的结构约束块（纯文本，非坐标画进图）。
  String toPromptBlock() {
    final buf = StringBuffer();
    buf.writeln('SCENE UNDERSTANDING (must preserve architecture):');
    if (roomType.isNotEmpty) buf.writeln('- room_type: $roomType');
    if (summary.trim().isNotEmpty) buf.writeln('- summary: $summary');
    void dump(String label, List<RenovStructItem> items) {
      if (items.isEmpty) return;
      buf.writeln('- $label:');
      for (final it in items.take(12)) {
        buf.writeln('  · ${it.toPromptLine()}');
      }
    }

    dump('walls', walls);
    dump('doors', doors);
    dump('windows', windows);
    dump('furniture', furniture);
    if (keepHints.isNotEmpty) {
      buf.writeln('- keep: ${keepHints.join('; ')}');
    }
    return buf.toString();
  }

  String shortUiLine() {
    final parts = <String>[
      if (roomType.isNotEmpty && roomType != 'other') roomType,
      if (walls.isNotEmpty) '墙${walls.length}',
      if (doors.isNotEmpty) '门${doors.length}',
      if (windows.isNotEmpty) '窗${windows.length}',
      if (furniture.isNotEmpty) '家具${furniture.length}',
    ];
    if (parts.isEmpty) {
      return summary.trim().isEmpty ? '结构理解：空' : summary;
    }
    return '已理解：${parts.join(' · ')}';
  }

  /// 折叠态人话摘要（不上 cx/cy）。
  String humanFriendlySummary() {
    final room = _roomTypeZh(roomType);
    final bits = <String>[
      if (room.isNotEmpty) room,
      ...furniture.map(_itemLabel).where((e) => e.isNotEmpty).take(3),
      ...windows.map(_itemLabel).where((e) => e.isNotEmpty).take(2),
      ...doors.map(_itemLabel).where((e) => e.isNotEmpty).take(2),
    ];
    if (bits.isEmpty) {
      final s = summary.trim();
      return s.isEmpty ? 'AI 暂未识别到明确空间要素' : 'AI 识别到：$s';
    }
    return 'AI 识别到：${bits.join('・')}';
  }

  static String _roomTypeZh(String t) => switch (t) {
        'living_room' => '客厅',
        'bedroom' => '卧室',
        'kitchen' => '厨房',
        'bathroom' => '卫生间',
        'dining' => '餐厅',
        'study' => '书房',
        'other' => '',
        _ => t.isEmpty || t == 'other' ? '' : t,
      };

  static String _itemLabel(RenovStructItem it) {
    final d = it.desc.trim();
    if (d.isNotEmpty) return d;
    final n = it.name.trim();
    if (n.isEmpty) return '';
    const map = {
      'sofa': '沙发',
      'bed': '床',
      'table': '桌',
      'desk': '书桌',
      'chair': '椅',
      'cabinet': '柜',
      'tv': '电视',
      'entry': '门',
      'door': '门',
      'win': '窗',
      'window': '窗',
      'back_wall': '主墙',
    };
    final lower = n.toLowerCase();
    for (final e in map.entries) {
      if (lower.contains(e.key)) return e.value;
    }
    return n;
  }

  /// 真机/开发对照：逐条中心点（cx/cy 相对图 0～1；非轮廓）。
  List<String> detailLines({int maxPerKind = 8}) {
    final lines = <String>[
      if (roomType.isNotEmpty) 'room_type: $roomType',
      if (summary.trim().isNotEmpty) 'summary: $summary',
    ];
    void dump(String label, List<RenovStructItem> items) {
      if (items.isEmpty) return;
      lines.add('$label (${items.length}):');
      for (final it in items.take(maxPerKind)) {
        lines.add('  · ${it.toPromptLine()}');
      }
      if (items.length > maxPerKind) {
        lines.add('  · …另有 ${items.length - maxPerKind} 项');
      }
    }

    dump('walls', walls);
    dump('doors', doors);
    dump('windows', windows);
    dump('furniture', furniture);
    if (keepHints.isNotEmpty) {
      lines.add('keep: ${keepHints.join('; ')}');
    }
    return lines;
  }

  /// 可展开查看的紧凑 JSON（真机核对 schema）。
  String toPrettyJson() {
    final map = toJson();
    const encoder = JsonEncoder.withIndent('  ');
    try {
      return encoder.convert(map);
    } catch (_) {
      return '$map';
    }
  }
}

class RenovStructItem {
  RenovStructItem({
    required this.name,
    this.cx,
    this.cy,
    this.desc = '',
  });

  final String name;
  final double? cx;
  final double? cy;
  final String desc;

  factory RenovStructItem.fromJson(Map<String, dynamic> j) {
    double? n(dynamic v) => v is num ? v.toDouble() : null;
    return RenovStructItem(
      name: '${j['name'] ?? j['id'] ?? j['type'] ?? 'item'}',
      cx: n(j['cx'] ?? j['x']),
      cy: n(j['cy'] ?? j['y']),
      desc: '${j['desc'] ?? j['description'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (cx != null) 'cx': cx,
        if (cy != null) 'cy': cy,
        if (desc.isNotEmpty) 'desc': desc,
      };

  String toPromptLine() {
    final pos = (cx != null && cy != null)
        ? ' @(${cx!.toStringAsFixed(2)},${cy!.toStringAsFixed(2)})'
        : '';
    final d = desc.isEmpty ? '' : ' — $desc';
    return '$name$pos$d';
  }
}
