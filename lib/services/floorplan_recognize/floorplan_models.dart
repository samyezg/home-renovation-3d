/// I21 P0：户型图识别中间结果（相对坐标 0～1，相对图片宽高）。
class FloorplanAiResult {
  FloorplanAiResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.rooms,
    this.walls = const [],
    this.doors = const [],
    this.windows = const [],
    this.source = 'local',
    this.warnings = const [],
  });

  final int imageWidth;
  final int imageHeight;
  final List<AiRoom> rooms;
  final List<AiWall> walls;
  final List<AiDoor> doors;
  final List<AiWindow> windows;
  final String source; // local | vision_api
  final List<String> warnings;

  factory FloorplanAiResult.fromJson(Map<String, dynamic> j) {
    final size = j['image_size'] as Map<String, dynamic>? ?? {};
    return FloorplanAiResult(
      imageWidth: (size['width'] as num?)?.toInt() ?? 1000,
      imageHeight: (size['height'] as num?)?.toInt() ?? 1000,
      rooms: (j['rooms'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AiRoom.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      walls: (j['walls'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AiWall.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      doors: (j['doors'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AiDoor.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      windows: (j['windows'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AiWindow.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      source: j['source'] as String? ?? 'vision_api',
      warnings: (j['warnings'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}

class AiRoom {
  AiRoom({
    required this.id,
    required this.name,
    required this.type,
    required this.polygon,
  });

  final String id;
  final String name;
  final String type;
  /// 归一化多边形 [[x,y],...]，x/y ∈ [0,1]
  final List<List<double>> polygon;

  factory AiRoom.fromJson(Map<String, dynamic> j) {
    final raw = j['polygon'] as List? ?? [];
    final poly = <List<double>>[];
    for (final p in raw) {
      if (p is List && p.length >= 2) {
        poly.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
      }
    }
    return AiRoom(
      id: j['id'] as String? ?? 'r',
      name: j['name'] as String? ?? '房间',
      type: j['type'] as String? ?? 'other',
      polygon: poly,
    );
  }
}

class AiWall {
  AiWall({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.kind = 'exterior',
  });

  final String id;
  final double x1, y1, x2, y2;
  final String kind;

  factory AiWall.fromJson(Map<String, dynamic> j) => AiWall(
        id: j['id'] as String? ?? 'w',
        x1: (j['x1'] as num?)?.toDouble() ?? 0,
        y1: (j['y1'] as num?)?.toDouble() ?? 0,
        x2: (j['x2'] as num?)?.toDouble() ?? 0,
        y2: (j['y2'] as num?)?.toDouble() ?? 0,
        kind: j['type'] as String? ?? j['kind'] as String? ?? 'exterior',
      );
}

class AiDoor {
  AiDoor({
    required this.id,
    this.wallId,
    this.position = 0.5,
    this.width = 0.05,
    this.cx,
    this.cy,
  });

  final String id;
  final String? wallId;
  /// 沿所属墙的相对位置 0～1
  final double position;
  /// 归一化开口宽度（相对图面短边量级）
  final double width;
  /// 可选：图面归一化中心（优先于 wall_id+position）
  final double? cx;
  final double? cy;

  factory AiDoor.fromJson(Map<String, dynamic> j) {
    final center = j['center'] as List?;
    double? cx = (j['cx'] as num?)?.toDouble() ?? (j['x'] as num?)?.toDouble();
    double? cy = (j['cy'] as num?)?.toDouble() ?? (j['y'] as num?)?.toDouble();
    if (center != null && center.length >= 2) {
      cx ??= (center[0] as num?)?.toDouble();
      cy ??= (center[1] as num?)?.toDouble();
    }
    return AiDoor(
      id: j['id'] as String? ?? 'd',
      wallId: j['wall_id'] as String?,
      position: (j['position'] as num?)?.toDouble() ?? 0.5,
      width: (j['width'] as num?)?.toDouble() ?? 0.05,
      cx: cx,
      cy: cy,
    );
  }
}

class AiWindow {
  AiWindow({
    required this.id,
    this.wallId,
    this.position = 0.5,
    this.width = 0.08,
    this.cx,
    this.cy,
  });

  final String id;
  final String? wallId;
  final double position;
  final double width;
  final double? cx;
  final double? cy;

  factory AiWindow.fromJson(Map<String, dynamic> j) {
    final center = j['center'] as List?;
    double? cx = (j['cx'] as num?)?.toDouble() ?? (j['x'] as num?)?.toDouble();
    double? cy = (j['cy'] as num?)?.toDouble() ?? (j['y'] as num?)?.toDouble();
    if (center != null && center.length >= 2) {
      cx ??= (center[0] as num?)?.toDouble();
      cy ??= (center[1] as num?)?.toDouble();
    }
    return AiWindow(
      id: j['id'] as String? ?? 'win',
      wallId: j['wall_id'] as String?,
      position: (j['position'] as num?)?.toDouble() ?? 0.5,
      width: (j['width'] as num?)?.toDouble() ?? 0.08,
      cx: cx,
      cy: cy,
    );
  }
}

/// 比例尺：某条归一化边的实际长度（cm）
class ScaleInfo {
  ScaleInfo({
    required this.edgeNormLength,
    required this.realLengthCm,
  });

  final double edgeNormLength;
  final double realLengthCm;

  double get cmPerNorm =>
      edgeNormLength <= 1e-6 ? 1000 : realLengthCm / edgeNormLength;
}

class ScaleEdgeOption {
  ScaleEdgeOption({
    required this.id,
    required this.label,
    required this.normLength,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    this.isBayWidth = true,
    this.roomType = 'other',
  });

  final String id;
  final String label;
  final double normLength;
  final double ax, ay, bx, by;
  /// 横向边（开间/面宽方向）
  final bool isBayWidth;
  final String roomType;
}
