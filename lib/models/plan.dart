import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../core/constants.dart';

class PlanDocument {
  PlanDocument({
    required this.schemaVersion,
    required this.meta,
    required this.building,
    required this.walls,
    required this.rooms,
    required this.doors,
    List<WindowOpening>? windows,
    List<FurnitureItem>? furniture,
    this.constraints = const [],
    Annotations? annotations,
  })  : windows = windows ?? [],
        furniture = furniture ?? [],
        annotations = annotations ?? Annotations();

  int schemaVersion;
  PlanMeta meta;
  BuildingInfo building;
  List<WallSeg> walls;
  List<RoomRect> rooms;
  List<DoorOpening> doors;
  List<WindowOpening> windows;
  /// I11：画布布置家具（单向同步至 3D）
  List<FurnitureItem> furniture;
  List<ConstraintMark> constraints;
  Annotations annotations;

  factory PlanDocument.create({
    String name = '未命名方案',
    BuildingInfo? building,
  }) {
    final now = DateTime.now().toIso8601String();
    final id = 'plan_${const Uuid().v4().substring(0, 8)}';
    return PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: id,
        name: name,
        createdAt: now,
        updatedAt: now,
      ),
      building: building ?? BuildingInfo(),
      walls: [],
      rooms: [],
      doors: [],
    );
  }

  factory PlanDocument.fromJson(Map<String, dynamic> j) {
    return PlanDocument(
      schemaVersion: j['schema_version'] as int? ?? 1,
      meta: PlanMeta.fromJson(j['meta'] as Map<String, dynamic>? ?? {}),
      building: BuildingInfo.fromJson(j['building'] as Map<String, dynamic>? ?? {}),
      walls: (j['walls'] as List? ?? [])
          .map((e) => WallSeg.fromJson(e as Map<String, dynamic>))
          .toList(),
      rooms: (j['rooms'] as List? ?? [])
          .map((e) => RoomRect.fromJson(e as Map<String, dynamic>))
          .toList(),
      doors: (j['doors'] as List? ?? [])
          .map((e) => DoorOpening.fromJson(e as Map<String, dynamic>))
          .toList(),
      windows: (j['windows'] as List? ?? [])
          .whereType<Map>()
          .map((e) => WindowOpening.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      furniture: (j['furniture'] as List? ?? [])
          .whereType<Map>()
          .map((e) => FurnitureItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      constraints: (j['constraints'] as List? ?? [])
          .map((e) => ConstraintMark.fromJson(e as Map<String, dynamic>))
          .toList(),
      annotations: Annotations.fromJson(
        j['annotations'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'meta': meta.toJson(),
        'building': building.toJson(),
        'walls': walls.map((e) => e.toJson()).toList(),
        'rooms': rooms.map((e) => e.toJson()).toList(),
        'doors': doors.map((e) => e.toJson()).toList(),
        'windows': windows.map((e) => e.toJson()).toList(),
        'furniture': furniture.map((e) => e.toJson()).toList(),
        'constraints': constraints.map((e) => e.toJson()).toList(),
        'annotations': annotations.toJson(),
      };

  String encodePretty() => const JsonEncoder.withIndent('  ').convert(toJson());

  void touch() {
    meta.updatedAt = DateTime.now().toIso8601String();
  }

  /// 期次 U：撤销一档——用 JSON 快照恢复几何内容（保留本地方案 id）
  void restoreFromJson(Map<String, dynamic> j) {
    final src = PlanDocument.fromJson(j);
    final keepId = meta.id;
    final keepCreated = meta.createdAt;
    schemaVersion = src.schemaVersion;
    meta = src.meta;
    meta.id = keepId;
    meta.createdAt = keepCreated;
    building = src.building;
    walls = src.walls;
    rooms = src.rooms;
    doors = src.doors;
    windows = src.windows;
    furniture = src.furniture;
    constraints = src.constraints;
    annotations = src.annotations;
  }

  /// 从房间轮廓生成墙网：共边为 partition，单侧为 exterior。
  /// 有 [RoomRect.polygon] 时只用多边形边（跳过 AABB）；近轴对齐边参与共边检测，斜边一律 exterior。
  void rebuildWallsFromRooms() {
    if (rooms.isEmpty) {
      walls = [];
      return;
    }

    double snap1(double v) => v.roundToDouble();

    // 水平边：y → [(xStart, xEnd, roomId), ...]；竖直边：x → [(yStart, yEnd, roomId), ...]
    final horiz = <double, List<(double, double, String)>>{};
    final vert = <double, List<(double, double, String)>>{};
    final diagonal = <(double, double, double, double)>[];

    void addH(double y, double xA, double xB, String roomId) {
      y = snap1(y);
      xA = snap1(xA);
      xB = snap1(xB);
      if (xA > xB) {
        final t = xA;
        xA = xB;
        xB = t;
      }
      if (xB - xA < 1) return;
      horiz.putIfAbsent(y, () => []).add((xA, xB, roomId));
    }

    void addV(double x, double yA, double yB, String roomId) {
      x = snap1(x);
      yA = snap1(yA);
      yB = snap1(yB);
      if (yA > yB) {
        final t = yA;
        yA = yB;
        yB = t;
      }
      if (yB - yA < 1) return;
      vert.putIfAbsent(x, () => []).add((yA, yB, roomId));
    }

    for (final r in rooms) {
      final poly = r.polygon;
      if (poly != null && poly.length >= 3) {
        for (var i = 0; i < poly.length; i++) {
          final a = poly[i];
          final b = poly[(i + 1) % poly.length];
          if (a.length < 2 || b.length < 2) continue;
          final ax = a[0], ay = a[1], bx = b[0], by = b[1];
          if ((ay - by).abs() <= 2) {
            addH((ay + by) / 2, ax, bx, r.id);
          } else if ((ax - bx).abs() <= 2) {
            addV((ax + bx) / 2, ay, by, r.id);
          } else {
            diagonal.add((snap1(ax), snap1(ay), snap1(bx), snap1(by)));
          }
        }
        continue;
      }
      final x0 = snap1(r.x);
      final y0 = snap1(r.y);
      final x1 = snap1(r.x + r.widthCm);
      final y1 = snap1(r.y + r.depthCm);
      addH(y0, x0, x1, r.id); // top
      addH(y1, x0, x1, r.id); // bottom
      addV(x0, y0, y1, r.id); // left
      addV(x1, y0, y1, r.id); // right
    }

    /// 将坐标相差 ≤ tol 的线合并到同一代表坐标。
    /// Y2：tol = max(2cm, 跨度×0.1%)，避免误封客厅–阳台等开口。
    Map<double, List<(double, double, String)>> clusterLines(
      Map<double, List<(double, double, String)>> raw,
      double tol,
    ) {
      if (raw.isEmpty) return raw;
      final keys = raw.keys.toList()..sort();
      final clustered = <double, List<(double, double, String)>>{};
      var cluster = <double>[keys.first];
      void flush() {
        final rep = cluster.reduce((a, b) => a + b) / cluster.length;
        final merged = <(double, double, String)>[];
        for (final k in cluster) {
          merged.addAll(raw[k]!);
        }
        clustered[rep] = merged;
        cluster = [];
      }

      for (var i = 1; i < keys.length; i++) {
        if (keys[i] - cluster.last <= tol) {
          cluster.add(keys[i]);
        } else {
          flush();
          cluster = [keys[i]];
        }
      }
      flush();
      return clustered;
    }

    // 平面跨度估算（用于相对容差）
    var minC = double.infinity, maxC = -double.infinity;
    for (final r in rooms) {
      final poly = r.polygon;
      if (poly != null) {
        for (final p in poly) {
          if (p.length < 2) continue;
          minC = math.min(minC, math.min(p[0], p[1]));
          maxC = math.max(maxC, math.max(p[0], p[1]));
        }
      } else {
        minC = math.min(minC, math.min(r.x, r.y));
        maxC = math.max(maxC, math.max(r.x + r.widthCm, r.y + r.depthCm));
      }
    }
    final span = (maxC.isFinite && minC.isFinite) ? (maxC - minC) : 1000.0;
    final lineTol = math.max(
      AppConstants.coWallAbsTolCm,
      span * AppConstants.coWallRelTol,
    );

    /// 在一条直线上按覆盖次数切分为 exterior / partition 段。
    List<(double start, double end, String kind)> splitByCoverage(
      List<(double, double, String)> edges,
    ) {
      if (edges.isEmpty) return const [];
      final pts = <double>{};
      for (final e in edges) {
        pts.add(e.$1);
        pts.add(e.$2);
      }
      final sorted = pts.toList()..sort();
      final atomic = <(double, double, String)>[];
      for (var i = 0; i < sorted.length - 1; i++) {
        final a = sorted[i];
        final b = sorted[i + 1];
        if (b - a < 1) continue;
        final mid = (a + b) / 2;
        final roomsCovering = <String>{};
        for (final e in edges) {
          if (e.$1 <= mid && mid <= e.$2) roomsCovering.add(e.$3);
        }
        if (roomsCovering.isEmpty) continue;
        final kind = roomsCovering.length >= 2 ? 'partition' : 'exterior';
        atomic.add((a, b, kind));
      }
      if (atomic.isEmpty) return const [];
      // 合并同 kind 连续段
      final out = <(double, double, String)>[];
      var curS = atomic.first.$1;
      var curE = atomic.first.$2;
      var curK = atomic.first.$3;
      for (var i = 1; i < atomic.length; i++) {
        final s = atomic[i];
        if (s.$3 == curK && (s.$1 - curE).abs() < 1.5) {
          curE = s.$2;
        } else {
          out.add((curS, curE, curK));
          curS = s.$1;
          curE = s.$2;
          curK = s.$3;
        }
      }
      out.add((curS, curE, curK));
      return out;
    }

    final hLines = clusterLines(horiz, lineTol);
    final vLines = clusterLines(vert, lineTol);
    final result = <WallSeg>[];
    var wi = 0;

    for (final entry in hLines.entries) {
      final y = entry.key;
      for (final seg in splitByCoverage(entry.value)) {
        result.add(
          WallSeg(
            id: 'w_$wi',
            x1: seg.$1,
            y1: y,
            x2: seg.$2,
            y2: y,
            thicknessCm: 12,
            kind: seg.$3,
          ),
        );
        wi++;
      }
    }
    for (final entry in vLines.entries) {
      final x = entry.key;
      for (final seg in splitByCoverage(entry.value)) {
        result.add(
          WallSeg(
            id: 'w_$wi',
            x1: x,
            y1: seg.$1,
            x2: x,
            y2: seg.$2,
            thicknessCm: 12,
            kind: seg.$3,
          ),
        );
        wi++;
      }
    }

    for (final e in diagonal) {
      final dx = e.$3 - e.$1;
      final dy = e.$4 - e.$2;
      if (dx * dx + dy * dy < 1) continue;
      result.add(
        WallSeg(
          id: 'w_$wi',
          x1: e.$1,
          y1: e.$2,
          x2: e.$3,
          y2: e.$4,
          thicknessCm: 12,
          kind: 'exterior',
        ),
      );
      wi++;
    }

    // 期次 S/Y2：近似重合斜边合并；容差收紧
    walls = _mergeNearlyDuplicateDiagonals(
      result,
      math.max(3.0, span * 0.002),
    );
  }

  /// 端点均在 tol 内视为同一斜墙；保留一条并标 partition。
  static List<WallSeg> _mergeNearlyDuplicateDiagonals(
    List<WallSeg> input, [
    double tol = 4.0,
  ]) {
    bool near(double a, double b) => (a - b).abs() <= tol;
    bool sameSeg(WallSeg a, WallSeg b) {
      final same =
          near(a.x1, b.x1) && near(a.y1, b.y1) && near(a.x2, b.x2) && near(a.y2, b.y2);
      final rev =
          near(a.x1, b.x2) && near(a.y1, b.y2) && near(a.x2, b.x1) && near(a.y2, b.y1);
      return same || rev;
    }

    final out = <WallSeg>[];
    final consumed = List<bool>.filled(input.length, false);
    for (var i = 0; i < input.length; i++) {
      if (consumed[i]) continue;
      final a = input[i];
      final isDiag = (a.x1 - a.x2).abs() > 2 && (a.y1 - a.y2).abs() > 2;
      if (!isDiag) {
        out.add(a);
        consumed[i] = true;
        continue;
      }
      var kind = a.kind;
      for (var j = i + 1; j < input.length; j++) {
        if (consumed[j]) continue;
        final b = input[j];
        final bDiag = (b.x1 - b.x2).abs() > 2 && (b.y1 - b.y2).abs() > 2;
        if (!bDiag) continue;
        if (sameSeg(a, b)) {
          kind = 'partition';
          consumed[j] = true;
        }
      }
      consumed[i] = true;
      a.kind = kind;
      out.add(a);
    }
    for (var i = 0; i < out.length; i++) {
      out[i].id = 'w_$i';
    }
    return out;
  }
}

class PlanMeta {
  PlanMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.origin = 'top_left',
    this.units = 'cm',
    this.canvasWidth = 2000,
    this.canvasHeight = 1500,
    this.gridCm = 10,
  });

  String id;
  String name;
  String createdAt;
  String updatedAt;
  String origin;
  String units;
  double canvasWidth;
  double canvasHeight;
  double gridCm;

  factory PlanMeta.fromJson(Map<String, dynamic> j) => PlanMeta(
        id: j['id'] as String? ?? 'plan_unknown',
        name: j['name'] as String? ?? '未命名',
        createdAt: j['created_at'] as String? ?? '',
        updatedAt: j['updated_at'] as String? ?? '',
        origin: j['origin'] as String? ?? 'top_left',
        units: j['units'] as String? ?? 'cm',
        canvasWidth: (j['canvas']?['width'] as num?)?.toDouble() ?? 2000,
        canvasHeight: (j['canvas']?['height'] as num?)?.toDouble() ?? 1500,
        gridCm: (j['canvas']?['grid_cm'] as num?)?.toDouble() ?? 10,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'origin': origin,
        'units': units,
        'canvas': {
          'width': canvasWidth,
          'height': canvasHeight,
          'grid_cm': gridCm,
        },
      };
}

class BuildingInfo {
  BuildingInfo({
    this.areaBuildM2 = 89,
    this.areaNetM2,
    this.floorHeightCm = AppConstants.floorHeightCm,
    this.roomCount = 3,
    this.bathroomCount = 1,
    this.cityName = '成都',
    this.cityTier = 'new_tier1',
    this.cityTierSource = 'auto',
    this.familyStage = 'newlywed',
    this.residents = 2,
    this.hasChildren = false,
    this.hasElderly = false,
    this.storageRatioSurvey,
    this.storageIntegrated = true,
    this.displayRatioOk = true,
    this.colorSchemeOk = true,
  });

  double areaBuildM2;
  double? areaNetM2;
  double floorHeightCm;
  int roomCount;
  int bathroomCount;
  String cityName;
  String cityTier;

  /// `auto`：随城市名按 2025 新一线榜建议；`manual`：用户手改级别后不再被城市名覆盖。
  String cityTierSource;
  String familyStage;
  int residents;
  bool hasChildren;
  bool hasElderly;

  /// 用户自估收纳投影占比 0~1；null 表示未填，引擎用均布代理。
  double? storageRatioSurvey;
  bool storageIntegrated;
  bool displayRatioOk;
  /// R011：1+1 配色是否已控制跳色
  bool colorSchemeOk;

  bool get cityTierIsManual => cityTierSource == 'manual';

  factory BuildingInfo.fromJson(Map<String, dynamic> j) => BuildingInfo(
        areaBuildM2: (j['area_build_m2'] as num?)?.toDouble() ?? 89,
        areaNetM2: (j['area_net_m2'] as num?)?.toDouble(),
        floorHeightCm:
            (j['floor_height_cm'] as num?)?.toDouble() ?? AppConstants.floorHeightCm,
        roomCount: j['room_count'] as int? ?? 3,
        bathroomCount: j['bathroom_count'] as int? ?? 1,
        cityName: j['city_name'] as String? ?? '成都',
        cityTier: j['city_tier'] as String? ?? 'new_tier1',
        cityTierSource: j['city_tier_source'] as String? ?? 'auto',
        familyStage: j['family_stage'] as String? ?? 'newlywed',
        residents: j['residents'] as int? ?? 2,
        hasChildren: j['has_children'] as bool? ?? false,
        hasElderly: j['has_elderly'] as bool? ?? false,
        storageRatioSurvey: (j['storage_ratio_survey'] as num?)?.toDouble(),
        storageIntegrated: j['storage_integrated'] as bool? ?? true,
        displayRatioOk: j['display_ratio_ok'] as bool? ?? true,
        colorSchemeOk: j['color_scheme_ok'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'area_build_m2': areaBuildM2,
        'area_net_m2': areaNetM2,
        'floor_height_cm': floorHeightCm,
        'room_count': roomCount,
        'bathroom_count': bathroomCount,
        'city_name': cityName,
        'city_tier': cityTier,
        'city_tier_source': cityTierSource,
        'family_stage': familyStage,
        'residents': residents,
        'has_children': hasChildren,
        'has_elderly': hasElderly,
        'storage_ratio_survey': storageRatioSurvey,
        'storage_integrated': storageIntegrated,
        'display_ratio_ok': displayRatioOk,
        'color_scheme_ok': colorSchemeOk,
      };
}

class WallSeg {
  WallSeg({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.thicknessCm = 12,
    this.kind = 'partition',
  });

  String id;
  double x1, y1, x2, y2;
  double thicknessCm;
  String kind;

  factory WallSeg.fromJson(Map<String, dynamic> j) => WallSeg(
        id: j['id'] as String,
        x1: (j['x1'] as num).toDouble(),
        y1: (j['y1'] as num).toDouble(),
        x2: (j['x2'] as num).toDouble(),
        y2: (j['y2'] as num).toDouble(),
        thicknessCm: (j['thickness_cm'] as num?)?.toDouble() ?? 12,
        kind: j['kind'] as String? ?? 'partition',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'thickness_cm': thicknessCm,
        'kind': kind,
      };
}

class RoomRect {
  RoomRect({
    required this.id,
    required this.name,
    required this.type,
    required this.x,
    required this.y,
    required this.widthCm,
    required this.depthCm,
    this.hasStorageZone = false,
    this.shape = 'rect',
    this.polygon,
  });

  String id;
  String name;
  String type;
  double x, y, widthCm, depthCm;
  bool hasStorageZone;
  String shape;

  /// 可选多边形顶点 `[[x,y], ...]`（cm）；闭合隐含。非 null 时 x/y/width/depth 为其 AABB。
  List<List<double>>? polygon;

  bool get hasPolygon => polygon != null && polygon!.length >= 3;

  factory RoomRect.fromJson(Map<String, dynamic> j) {
    List<List<double>>? poly;
    final raw = j['polygon'];
    if (raw is List && raw.length >= 3) {
      poly = [];
      for (final pt in raw) {
        if (pt is List && pt.length >= 2) {
          poly.add([
            (pt[0] as num).toDouble(),
            (pt[1] as num).toDouble(),
          ]);
        } else if (pt is Map) {
          poly.add([
            (pt['x'] as num?)?.toDouble() ?? 0,
            (pt['y'] as num?)?.toDouble() ?? 0,
          ]);
        }
      }
      if (poly.length < 3) poly = null;
    }
    return RoomRect(
      id: j['id'] as String,
      name: j['name'] as String? ?? j['type'] as String? ?? '房间',
      type: j['type'] as String? ?? 'other',
      x: (j['x'] as num?)?.toDouble() ?? 0,
      y: (j['y'] as num?)?.toDouble() ?? 0,
      widthCm: (j['width_cm'] as num?)?.toDouble() ?? 300,
      depthCm: (j['depth_cm'] as num?)?.toDouble() ?? 300,
      hasStorageZone: j['has_storage_zone'] as bool? ?? false,
      shape: j['shape'] as String? ?? (poly != null ? 'polygon' : 'rect'),
      polygon: poly,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'shape': shape,
      'x': x,
      'y': y,
      'width_cm': widthCm,
      'depth_cm': depthCm,
      'has_storage_zone': hasStorageZone,
    };
    if (polygon != null && polygon!.length >= 3) {
      m['polygon'] = polygon!
          .map((p) => [p[0], p[1]])
          .toList(growable: false);
    }
    return m;
  }

  /// 按多边形重算 AABB（不改顶点）。
  void syncAabbFromPolygon() {
    final poly = polygon;
    if (poly == null || poly.length < 3) return;
    var minX = poly.first[0], maxX = poly.first[0];
    var minY = poly.first[1], maxY = poly.first[1];
    for (final p in poly) {
      if (p[0] < minX) minX = p[0];
      if (p[0] > maxX) maxX = p[0];
      if (p[1] < minY) minY = p[1];
      if (p[1] > maxY) maxY = p[1];
    }
    x = minX;
    y = minY;
    widthCm = (maxX - minX).clamp(80, 5000);
    depthCm = (maxY - minY).clamp(80, 5000);
  }

  /// 平移房间；若有多边形则同步平移顶点。
  void translateBy(double dx, double dy) {
    x += dx;
    y += dy;
    final poly = polygon;
    if (poly == null) return;
    for (final p in poly) {
      p[0] += dx;
      p[1] += dy;
    }
  }

  /// 将 AABB 设为新值，并按相对比例变换多边形顶点。
  void setAabbTransformingPolygon(
    double newX,
    double newY,
    double newW,
    double newD,
  ) {
    final poly = polygon;
    if (poly == null || poly.length < 3 || widthCm < 1 || depthCm < 1) {
      x = newX;
      y = newY;
      widthCm = newW;
      depthCm = newD;
      return;
    }
    final ox = x, oy = y, ow = widthCm, od = depthCm;
    for (final p in poly) {
      final u = (p[0] - ox) / ow;
      final v = (p[1] - oy) / od;
      p[0] = newX + u * newW;
      p[1] = newY + v * newD;
    }
    x = newX;
    y = newY;
    widthCm = newW;
    depthCm = newD;
  }

  /// 矩形 → 四顶点多边形（顺时针：左上→右上→右下→左下）。
  void ensurePolygonFromRect() {
    if (hasPolygon) {
      shape = 'polygon';
      return;
    }
    polygon = [
      [x, y],
      [x + widthCm, y],
      [x + widthCm, y + depthCm],
      [x, y + depthCm],
    ];
    shape = 'polygon';
  }

  /// 在顶点 [vertexIndex] 切角：用沿两边内缩 [cutCm] 的两点替换原顶点。
  /// 成功返回 true；过短边或顶点过少则 false。
  bool chamferVertex(int vertexIndex, double cutCm) {
    ensurePolygonFromRect();
    final poly = polygon;
    if (poly == null || poly.length < 3) return false;
    final n = poly.length;
    if (vertexIndex < 0 || vertexIndex >= n) return false;
    final cut = cutCm.clamp(20.0, 400.0);
    final prev = poly[(vertexIndex - 1 + n) % n];
    final curr = poly[vertexIndex];
    final next = poly[(vertexIndex + 1) % n];

    double len(List<double> a, List<double> b) {
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      return math.sqrt(dx * dx + dy * dy);
    }

    final lenPrev = len(curr, prev);
    final lenNext = len(curr, next);
    if (lenPrev < cut * 2 + 1 || lenNext < cut * 2 + 1) return false;

    List<double> along(List<double> from, List<double> to, double dist) {
      final dx = to[0] - from[0];
      final dy = to[1] - from[1];
      final L = math.sqrt(dx * dx + dy * dy);
      return [from[0] + dx / L * dist, from[1] + dy / L * dist];
    }

    final a = along(curr, prev, cut);
    final b = along(curr, next, cut);
    final nextPoly = <List<double>>[];
    for (var i = 0; i < n; i++) {
      if (i == vertexIndex) {
        nextPoly.add(a);
        nextPoly.add(b);
      } else {
        nextPoly.add([poly[i][0], poly[i][1]]);
      }
    }
    polygon = nextPoly;
    shape = 'polygon';
    syncAabbFromPolygon();
    return true;
  }

  /// 移动多边形顶点（cm），并刷新 AABB。
  void moveVertex(int vertexIndex, double nx, double ny) {
    final poly = polygon;
    if (poly == null || vertexIndex < 0 || vertexIndex >= poly.length) return;
    poly[vertexIndex][0] = nx;
    poly[vertexIndex][1] = ny;
    shape = 'polygon';
    syncAabbFromPolygon();
  }

  /// 删除顶点（至少保留 3 点）。
  bool removeVertex(int vertexIndex) {
    final poly = polygon;
    if (poly == null || poly.length <= 3) return false;
    if (vertexIndex < 0 || vertexIndex >= poly.length) return false;
    poly.removeAt(vertexIndex);
    syncAabbFromPolygon();
    return true;
  }

  /// 点到多边形各边的最短距离（cm）；无多边形时用 AABB 边。
  double minDistanceToEdges(double px, double py) {
    final edges = _edgeSegments();
    var best = double.infinity;
    for (final e in edges) {
      final d = _distPointToSegment(px, py, e.$1, e.$2, e.$3, e.$4);
      if (d < best) best = d;
    }
    return best;
  }

  /// 是否与墙中点「贴边」（多边形用真实边，容差 cm）。
  bool wallTouchesByEdges(double wx1, double wy1, double wx2, double wy2,
      {double tol = 18}) {
    final mx = (wx1 + wx2) / 2;
    final my = (wy1 + wy2) / 2;
    if (minDistanceToEdges(mx, my) <= tol) return true;
    // 端点也贴边则算
    if (minDistanceToEdges(wx1, wy1) <= tol) return true;
    if (minDistanceToEdges(wx2, wy2) <= tol) return true;
    return false;
  }

  List<(double, double, double, double)> _edgeSegments() {
    if (hasPolygon) {
      final poly = polygon!;
      final n = poly.length;
      return [
        for (var i = 0; i < n; i++)
          (
            poly[i][0],
            poly[i][1],
            poly[(i + 1) % n][0],
            poly[(i + 1) % n][1],
          ),
      ];
    }
    return [
      (x, y, x + widthCm, y),
      (x + widthCm, y, x + widthCm, y + depthCm),
      (x + widthCm, y + depthCm, x, y + depthCm),
      (x, y + depthCm, x, y),
    ];
  }

  static double _distPointToSegment(
    double px,
    double py,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-6) {
      final ex = px - x1;
      final ey = py - y1;
      return math.sqrt(ex * ex + ey * ey);
    }
    var t = ((px - x1) * dx + (py - y1) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final qx = x1 + t * dx;
    final qy = y1 + t * dy;
    final ex = px - qx;
    final ey = py - qy;
    return math.sqrt(ex * ex + ey * ey);
  }
}

class DoorOpening {
  DoorOpening({
    required this.id,
    required this.roomId,
    this.wallId,
    this.centerCm = 100,
    this.widthCm = AppConstants.defaultDoorWidthCm,
    this.positionType = 'I',
    this.doorType = 'swing',
    this.swing = 'unknown',
  });

  String id;
  String roomId;
  String? wallId;
  double centerCm;
  double widthCm;

  /// O / I / II（开向/走道语义，诊断用）
  String positionType;

  /// swing / sliding / folding / double（门型）
  String doorType;
  String swing;

  factory DoorOpening.fromJson(Map<String, dynamic> j) {
    final pos = j['position_type'] as String? ?? 'I';
    var doorType = j['door_type'] as String?;
    // 旧数据：II 默认映射为推拉门
    doorType ??= (pos == 'II' ? 'sliding' : 'swing');
    return DoorOpening(
      id: j['id'] as String,
      roomId: j['room_id'] as String? ?? '',
      wallId: j['wall_id'] as String?,
      centerCm: (j['center_cm'] as num?)?.toDouble() ?? 100,
      widthCm: (j['width_cm'] as num?)?.toDouble() ??
          AppConstants.defaultDoorWidthCm,
      positionType: pos,
      doorType: doorType,
      swing: j['swing'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'wall_id': wallId,
        'center_cm': centerCm,
        'width_cm': widthCm,
        'position_type': positionType,
        'door_type': doorType,
        'swing': swing,
      };
}

/// 窗户开口（I12）：普通窗 / 落地窗 / 飘窗
class WindowOpening {
  WindowOpening({
    required this.id,
    required this.roomId,
    this.wallId,
    this.centerCm = 100,
    this.widthCm = AppConstants.defaultWindowWidthCm,
    this.heightCm = AppConstants.defaultWindowHeightCm,
    this.sillCm = AppConstants.defaultWindowSillCm,
    this.type = 'normal',
  });

  String id;
  String roomId;
  String? wallId;
  double centerCm;
  double widthCm;
  double heightCm;
  double sillCm;

  /// normal / floor / bay
  String type;

  factory WindowOpening.fromJson(Map<String, dynamic> j) => WindowOpening(
        id: j['id'] as String,
        roomId: j['room_id'] as String? ?? '',
        wallId: j['wall_id'] as String?,
        centerCm: (j['center_cm'] as num?)?.toDouble() ?? 100,
        widthCm: (j['width_cm'] as num?)?.toDouble() ??
            AppConstants.defaultWindowWidthCm,
        heightCm: (j['height_cm'] as num?)?.toDouble() ??
            AppConstants.defaultWindowHeightCm,
        sillCm: (j['sill_cm'] as num?)?.toDouble() ??
            AppConstants.defaultWindowSillCm,
        type: j['type'] as String? ?? 'normal',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'wall_id': wallId,
        'center_cm': centerCm,
        'width_cm': widthCm,
        'height_cm': heightCm,
        'sill_cm': sillCm,
        'type': type,
      };
}

/// I11：画布家具（顶视图布置；3D 只读加载）
class FurnitureItem {
  FurnitureItem({
    required this.id,
    required this.type,
    required this.roomId,
    required this.x,
    required this.y,
    this.rotation = 0,
    required this.widthCm,
    required this.depthCm,
    required this.heightCm,
  });

  String id;
  /// 与 SceneCatalog.sku_id 对齐，如 furn_sofa / cab_60
  String type;
  String roomId;
  /// 画布坐标：家具中心（cm，与房间同坐标系）
  double x;
  double y;
  /// 度，90° 步进
  double rotation;
  double widthCm;
  double depthCm;
  double heightCm;

  factory FurnitureItem.fromJson(Map<String, dynamic> j) => FurnitureItem(
        id: j['id'] as String,
        type: j['type'] as String? ?? j['sku_id'] as String? ?? 'furn_sofa',
        roomId: j['room_id'] as String? ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
        widthCm: (j['width_cm'] as num?)?.toDouble() ?? 100,
        depthCm: (j['depth_cm'] as num?)?.toDouble() ?? 60,
        heightCm: (j['height_cm'] as num?)?.toDouble() ?? 80,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'sku_id': type,
        'room_id': roomId,
        'x': x,
        'y': y,
        'rotation': rotation,
        'width_cm': widthCm,
        'depth_cm': depthCm,
        'height_cm': heightCm,
      };
}

class ConstraintMark {
  ConstraintMark({
    required this.id,
    required this.type,
    this.wallId,
    this.note,
  });

  String id;
  String type;
  String? wallId;
  String? note;

  factory ConstraintMark.fromJson(Map<String, dynamic> j) => ConstraintMark(
        id: j['id'] as String,
        type: j['type'] as String? ?? 'load_bearing',
        wallId: j['wall_id'] as String?,
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'wall_id': wallId,
        'note': note,
      };
}

class Annotations {
  Annotations({
    this.redRulerCm,
    this.blueRulerCm,
    this.openConnections = const [],
    this.screenshotPaths = const [],
    this.recognizeWarnings = const [],
    this.recognizeSource,
  });

  double? redRulerCm;
  double? blueRulerCm;
  List<String> openConnections;
  List<String> screenshotPaths;
  /// 识图/精校 warning（bad case 收集，随方案 JSON 导出）
  List<String> recognizeWarnings;
  /// local | vision_api | …
  String? recognizeSource;

  factory Annotations.fromJson(Map<String, dynamic> j) => Annotations(
        redRulerCm: (j['red_ruler_cm'] as num?)?.toDouble(),
        blueRulerCm: (j['blue_ruler_cm'] as num?)?.toDouble(),
        openConnections:
            (j['open_connections'] as List?)?.map((e) => '$e').toList() ??
                const [],
        screenshotPaths:
            (j['screenshot_paths'] as List?)?.map((e) => '$e').toList() ??
                const [],
        recognizeWarnings:
            (j['recognize_warnings'] as List?)?.map((e) => '$e').toList() ??
                const [],
        recognizeSource: j['recognize_source'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'red_ruler_cm': redRulerCm,
        'blue_ruler_cm': blueRulerCm,
        'open_connections': openConnections,
        'screenshot_paths': screenshotPaths,
        'recognize_warnings': recognizeWarnings,
        'recognize_source': recognizeSource,
      };
}
