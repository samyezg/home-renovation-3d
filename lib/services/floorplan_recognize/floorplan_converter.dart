import 'dart:math' as math;

import '../../core/constants.dart';
import '../../models/plan.dart';
import 'floorplan_models.dart';

/// AI/本地识别结果 → PlanDocument（cm）
class FloorplanConverter {
  FloorplanConverter._();

  /// 图面占比低于此值的边在比例尺排序中降权（避免 13% 短边当开间）
  static const double minPreferredEdgeNorm = 0.20;

  static String mapRoomType(String raw) {
    final t = raw.toLowerCase();
    if (t.contains('living') || t.contains('客厅') || t == 'living_room') {
      return 'living';
    }
    if (t.contains('bed') || t.contains('卧') || t == 'bedroom') return 'bed';
    if (t.contains('kitchen') || t.contains('厨')) return 'kitchen';
    if (t.contains('bath') || t.contains('卫') || t.contains('厕')) {
      return 'bath';
    }
    if (t.contains('study') || t.contains('书')) return 'study';
    if (t.contains('dining') || t.contains('餐')) return 'dining';
    if (t.contains('entry') || t.contains('玄关') || t.contains('门厅')) {
      return 'entry';
    }
    if (t.contains('balcon') || t.contains('阳')) return 'balcony';
    return 'other';
  }

  static List<ScaleEdgeOption> scaleEdgeOptions(FloorplanAiResult result) {
    final out = <ScaleEdgeOption>[];
    for (final r in result.rooms) {
      final poly = r.polygon;
      if (poly.length < 2) continue;
      var maxSpan = 0.0;
      var maxDepth = 0.0;
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        final dx = b[0] - a[0];
        final dy = b[1] - a[1];
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 0.05) continue;
        if (dx.abs() >= dy.abs()) {
          if (len > maxSpan) maxSpan = len;
        } else {
          if (len > maxDepth) maxDepth = len;
        }
      }
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        final dx = b[0] - a[0];
        final dy = b[1] - a[1];
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 0.05) continue;
        final isSpan = dx.abs() >= dy.abs();
        final midX = (a[0] + b[0]) / 2;
        final midY = (a[1] + b[1]) / 2;
        final side = isSpan
            ? (midY < 0.5 ? '图上侧墙' : '图下侧墙')
            : (midX < 0.5 ? '图左侧墙' : '图右侧墙');
        final role = isSpan ? '开间' : '进深';
        final isPrimary = isSpan
            ? (maxSpan > 0 && (len - maxSpan).abs() < 1e-6)
            : (maxDepth > 0 && (len - maxDepth).abs() < 1e-6);
        final short = len < minPreferredEdgeNorm;
        final hint = short
            ? '，偏短慎选'
            : (isPrimary && isSpan && mapRoomType(r.type) == 'living'
                ? '，常用作开间参照'
                : (isPrimary ? '，同向最长' : ''));
        out.add(
          ScaleEdgeOption(
            id: '${r.id}_$i',
            label:
                '${r.name}$role（$side，约图面 ${(len * 100).round()}%$hint）',
            normLength: len,
            ax: a[0],
            ay: a[1],
            bx: b[0],
            by: b[1],
            isBayWidth: isSpan,
            roomType: mapRoomType(r.type),
          ),
        );
      }
    }
    out.sort((a, b) {
      final sa = _scaleEdgeScore(a);
      final sb = _scaleEdgeScore(b);
      if (sa != sb) return sb.compareTo(sa);
      return b.normLength.compareTo(a.normLength);
    });
    return out;
  }

  static int _scaleEdgeScore(ScaleEdgeOption e) {
    var s = 0;
    if (e.isBayWidth) s += 10;
    if (e.roomType == 'living') s += 20;
    if (e.roomType == 'bed') s += 5;
    if (e.roomType == 'dining') s += 3;
    // 过短边强降权，避免默认「图面 13%」
    if (e.normLength < minPreferredEdgeNorm) s -= 40;
    if (e.normLength >= 0.28) s += 8;
    if (e.normLength >= 0.35) s += 6;
    return s;
  }

  /// 期次 V：去重 / 剔孤岛 / 非居住标注，返回清洗后的房间 + 警告。
  static ({List<AiRoom> rooms, List<String> warnings}) cleanRooms(
    List<AiRoom> input,
  ) {
    final warnings = <String>[];
    if (input.isEmpty) return (rooms: input, warnings: warnings);

    var rooms = List<AiRoom>.from(input);

    // 1) 剔除非居住噪声名
    final noiseName = RegExp(r'天井|上空|图签|指北|电梯井|管道井');
    final beforeNoise = rooms.length;
    rooms = rooms
        .where(
          (r) =>
              !(mapRoomType(r.type) == 'other' &&
                  noiseName.hasMatch(r.name)),
        )
        .toList();
    if (rooms.length < beforeNoise) {
      warnings.add('已隐藏 ${beforeNoise - rooms.length} 间标注类区域（如天井上空）');
    }

    // 2) 重叠去重：IoU 高则保留面积更大 / 类型更具体者
    rooms = _dedupeOverlapping(rooms, warnings);

    // 3) 主连通团：去掉远离主团的孤岛
    rooms = _keepMainCluster(rooms, warnings);

    return (rooms: rooms, warnings: warnings);
  }

  static List<AiRoom> _dedupeOverlapping(
    List<AiRoom> rooms,
    List<String> warnings,
  ) {
    if (rooms.length < 2) return rooms;
    final areas = [for (final r in rooms) _polyArea(r.polygon)];
    final drop = <int>{};
    for (var i = 0; i < rooms.length; i++) {
      if (drop.contains(i)) continue;
      for (var j = i + 1; j < rooms.length; j++) {
        if (drop.contains(j)) continue;
        final iou = _polyIou(rooms[i].polygon, rooms[j].polygon);
        if (iou < 0.35) continue;
        // 嵌套：小的若是卫浴且大的是卧室，保留两者但若 IoU>0.7 仍去小的重复卧室
        final ti = mapRoomType(rooms[i].type);
        final tj = mapRoomType(rooms[j].type);
        if (iou > 0.55) {
          // 同类型或卧室互叠：去较小
          if (ti == tj || (ti == 'bed' && tj == 'bed')) {
            if (areas[i] >= areas[j]) {
              drop.add(j);
            } else {
              drop.add(i);
            }
            continue;
          }
        }
        if (iou > 0.7) {
          // 强重叠：保留更具体（bath 嵌 living 少见；优先面积大）
          if (areas[i] >= areas[j]) {
            drop.add(j);
          } else {
            drop.add(i);
          }
        }
      }
    }
    if (drop.isNotEmpty) {
      warnings.add('已合并 ${drop.length} 间重叠识别房间');
    }
    return [
      for (var i = 0; i < rooms.length; i++)
        if (!drop.contains(i)) rooms[i],
    ];
  }

  static List<AiRoom> _keepMainCluster(
    List<AiRoom> rooms,
    List<String> warnings,
  ) {
    if (rooms.length <= 2) return rooms;
    final centers = [
      for (final r in rooms) _polyCentroid(r.polygon),
    ];
    // 以面积最大房为种子，BFS 邻接（边框接近）
    var seed = 0;
    var bestA = 0.0;
    for (var i = 0; i < rooms.length; i++) {
      final a = _polyArea(rooms[i].polygon);
      if (a > bestA) {
        bestA = a;
        seed = i;
      }
    }
    final inCluster = <int>{seed};
    final queue = <int>[seed];
    while (queue.isNotEmpty) {
      final i = queue.removeAt(0);
      for (var j = 0; j < rooms.length; j++) {
        if (inCluster.contains(j)) continue;
        if (_roomsAdjacent(rooms[i].polygon, rooms[j].polygon)) {
          inCluster.add(j);
          queue.add(j);
        }
      }
    }
    // 若主团过小，改用距离主质心
    if (inCluster.length < (rooms.length / 2).ceil()) {
      final mx = centers[seed][0];
      final my = centers[seed][1];
      inCluster
        ..clear()
        ..addAll([
          for (var i = 0; i < rooms.length; i++)
            if (math.sqrt(
                  math.pow(centers[i][0] - mx, 2) +
                      math.pow(centers[i][1] - my, 2),
                ) <
                0.42)
              i,
        ]);
      if (!inCluster.contains(seed)) inCluster.add(seed);
    }
    final removed = rooms.length - inCluster.length;
    if (removed > 0) {
      warnings.add('已排除 $removed 间远离主户型的孤岛房间');
    }
    return [
      for (var i = 0; i < rooms.length; i++)
        if (inCluster.contains(i)) rooms[i],
    ];
  }

  static bool _roomsAdjacent(List<List<double>> a, List<List<double>> b) {
    // 任一边中点到另一多边形的最小边距
    for (var i = 0; i < a.length; i++) {
      final p = a[i];
      final q = a[(i + 1) % a.length];
      final mid = [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
      if (_minDistPointToEdges(mid, b) < 0.035) return true;
    }
    for (var i = 0; i < b.length; i++) {
      final p = b[i];
      final q = b[(i + 1) % b.length];
      final mid = [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2];
      if (_minDistPointToEdges(mid, a) < 0.035) return true;
    }
    // 中心距兜底
    final ca = _polyCentroid(a);
    final cb = _polyCentroid(b);
    final d = math.sqrt(
      math.pow(ca[0] - cb[0], 2) + math.pow(ca[1] - cb[1], 2),
    );
    return d < 0.22;
  }

  static double _minDistPointToEdges(List<double> p, List<List<double>> poly) {
    var best = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      best = math.min(best, _distPointSeg(p[0], p[1], a[0], a[1], b[0], b[1]));
    }
    return best;
  }

  static double _distPointSeg(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-12) {
      return math.sqrt(math.pow(px - ax, 2) + math.pow(py - ay, 2));
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final qx = ax + t * dx;
    final qy = ay + t * dy;
    return math.sqrt(math.pow(px - qx, 2) + math.pow(py - qy, 2));
  }

  static double _polyArea(List<List<double>> poly) {
    if (poly.length < 3) return 0;
    var s = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      s += a[0] * b[1] - b[0] * a[1];
    }
    return s.abs() * 0.5;
  }

  static List<double> _polyCentroid(List<List<double>> poly) {
    if (poly.isEmpty) return [0.5, 0.5];
    var x = 0.0, y = 0.0;
    for (final p in poly) {
      x += p[0];
      y += p[1];
    }
    return [x / poly.length, y / poly.length];
  }

  static double _polyIou(List<List<double>> a, List<List<double>> b) {
    final aa = _aabb(a);
    final bb = _aabb(b);
    final ix0 = math.max(aa[0], bb[0]);
    final iy0 = math.max(aa[1], bb[1]);
    final ix1 = math.min(aa[2], bb[2]);
    final iy1 = math.min(aa[3], bb[3]);
    final iw = ix1 - ix0;
    final ih = iy1 - iy0;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final areaA = math.max(0.0, (aa[2] - aa[0]) * (aa[3] - aa[1]));
    final areaB = math.max(0.0, (bb[2] - bb[0]) * (bb[3] - bb[1]));
    final uni = areaA + areaB - inter;
    if (uni <= 1e-9) return 0;
    return inter / uni;
  }

  static List<double> _aabb(List<List<double>> poly) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in poly) {
      minX = math.min(minX, p[0]);
      minY = math.min(minY, p[1]);
      maxX = math.max(maxX, p[0]);
      maxY = math.max(maxY, p[1]);
    }
    return [minX, minY, maxX, maxY];
  }

  /// 邻接边坐标贴齐（归一化），减轻双墙；Y2 容差收紧以免误封开口。
  static List<AiRoom> snapAdjacentEdges(List<AiRoom> rooms) {
    if (rooms.length < 2) return rooms;
    final snapTol = AppConstants.snapAdjacentNormTol;
    final polys = [
      for (final r in rooms)
        [for (final p in r.polygon) [p[0], p[1]]],
    ];
    for (var i = 0; i < polys.length; i++) {
      for (var j = i + 1; j < polys.length; j++) {
        for (var pi = 0; pi < polys[i].length; pi++) {
          for (var pj = 0; pj < polys[j].length; pj++) {
            final a = polys[i][pi];
            final b = polys[j][pj];
            if ((a[0] - b[0]).abs() < snapTol &&
                (a[1] - b[1]).abs() < snapTol) {
              final mx = (a[0] + b[0]) / 2;
              final my = (a[1] + b[1]) / 2;
              a[0] = mx;
              a[1] = my;
              b[0] = mx;
              b[1] = my;
            }
          }
        }
        // 平行近边：把 j 的边投影贴到 i
        _snapParallelEdges(polys[i], polys[j], snapTol);
      }
    }
    return [
      for (var i = 0; i < rooms.length; i++)
        AiRoom(
          id: rooms[i].id,
          name: rooms[i].name,
          type: rooms[i].type,
          polygon: polys[i],
        ),
    ];
  }

  static void _snapParallelEdges(
    List<List<double>> a,
    List<List<double>> b,
    double tol,
  ) {
    for (var i = 0; i < a.length; i++) {
      final a0 = a[i];
      final a1 = a[(i + 1) % a.length];
      final aDx = a1[0] - a0[0];
      final aDy = a1[1] - a0[1];
      final aHoriz = aDx.abs() >= aDy.abs();
      for (var j = 0; j < b.length; j++) {
        final b0 = b[j];
        final b1 = b[(j + 1) % b.length];
        final bDx = b1[0] - b0[0];
        final bDy = b1[1] - b0[1];
        final bHoriz = bDx.abs() >= bDy.abs();
        if (aHoriz != bHoriz) continue;
        if (aHoriz) {
          if ((a0[1] - b0[1]).abs() > tol) continue;
          // 检查 x 投影重叠
          final aMin = math.min(a0[0], a1[0]);
          final aMax = math.max(a0[0], a1[0]);
          final bMin = math.min(b0[0], b1[0]);
          final bMax = math.max(b0[0], b1[0]);
          if (aMax < bMin - tol || bMax < aMin - tol) continue;
          final y = (a0[1] + a1[1] + b0[1] + b1[1]) / 4;
          a0[1] = y;
          a1[1] = y;
          b0[1] = y;
          b1[1] = y;
        } else {
          if ((a0[0] - b0[0]).abs() > tol) continue;
          final aMin = math.min(a0[1], a1[1]);
          final aMax = math.max(a0[1], a1[1]);
          final bMin = math.min(b0[1], b1[1]);
          final bMax = math.max(b0[1], b1[1]);
          if (aMax < bMin - tol || bMax < aMin - tol) continue;
          final x = (a0[0] + a1[0] + b0[0] + b1[0]) / 4;
          a0[0] = x;
          a1[0] = x;
          b0[0] = x;
          b1[0] = x;
        }
      }
    }
  }

  static PlanDocument toPlan(
    FloorplanAiResult result,
    ScaleInfo scale, {
    String? name,
    BuildingInfo? building,
  }) {
    final s = scale.cmPerNorm;
    final plan = PlanDocument.create(
      name: name ?? '拍照识别户型',
      building: building,
    );

    final cleaned = cleanRooms(result.rooms);
    final snapped = snapAdjacentEdges(cleaned.rooms);
    for (final ar in snapped) {
      if (ar.polygon.length < 3) continue;
      final polyCm = <List<double>>[
        for (final p in ar.polygon) [p[0] * s, p[1] * s],
      ];
      final room = RoomRect(
        id: ar.id.startsWith('r') ? ar.id : 'room_${ar.id}',
        name: ar.name,
        type: mapRoomType(ar.type),
        x: 0,
        y: 0,
        widthCm: 300,
        depthCm: 300,
        shape: 'polygon',
        polygon: polyCm,
      );
      room.syncAabbFromPolygon();
      plan.rooms.add(room);
    }

    plan.rebuildWallsFromRooms();

    _placeOpenings(
      plan: plan,
      result: result,
      scale: scale,
    );

    final area = plan.rooms.fold<double>(0, (a, r) {
      return a + (r.widthCm * r.depthCm) / 10000.0;
    });
    if (plan.building.areaBuildM2 <= 0 && area > 0) {
      plan.building.areaBuildM2 = double.parse((area / 0.8).toStringAsFixed(1));
    }
    plan.building.roomCount =
        plan.rooms.where((r) => r.type == 'bed' || r.type == 'living').length;
    plan.building.bathroomCount =
        plan.rooms.where((r) => r.type == 'bath').length;
    plan.touch();
    return plan;
  }

  /// 门窗：图面点 → 投影到最近墙段（不再「一律贴最长墙」）。
  static void _placeOpenings({
    required PlanDocument plan,
    required FloorplanAiResult result,
    required ScaleInfo scale,
  }) {
    if (plan.rooms.isEmpty || plan.walls.isEmpty) return;
    final s = scale.cmPerNorm;

    for (final ad in result.doors) {
      final pt = _openingNormPoint(
        wallId: ad.wallId,
        position: ad.position,
        cx: ad.cx,
        cy: ad.cy,
        aiWalls: result.walls,
        rooms: result.rooms,
        preferExterior: false,
      );
      if (pt == null) continue;
      final hit = _projectToNearestWall(
        plan,
        pt.$1 * s,
        pt.$2 * s,
        preferExterior: false,
      );
      if (hit == null) continue;
      final widthCm = _openingWidthCm(
        normWidth: ad.width,
        wallLenCm: hit.len,
        cmPerNorm: s,
        fallback: AppConstants.defaultDoorWidthCm,
        minCm: 70,
        maxCm: 100,
        maxWallFraction: 0.35,
      );
      final half = widthCm / 2;
      final center = hit.centerCm.clamp(half + 5, hit.len - half - 5);
      if (center <= half || center >= hit.len - half) continue;
      if (_overlapsExisting(
        plan.doors.map((d) => (d.wallId, d.centerCm, d.widthCm)),
        hit.wall.id,
        center,
        widthCm,
      )) {
        continue;
      }
      plan.doors.add(
        DoorOpening(
          id: ad.id,
          roomId: _nearestRoomId(plan, hit.wall),
          wallId: hit.wall.id,
          centerCm: center.toDouble(),
          widthCm: widthCm,
          positionType: 'I',
          doorType: 'swing',
        ),
      );
    }

    for (final aw in result.windows) {
      final pt = _openingNormPoint(
        wallId: aw.wallId,
        position: aw.position,
        cx: aw.cx,
        cy: aw.cy,
        aiWalls: result.walls,
        rooms: result.rooms,
        preferExterior: true,
      );
      if (pt == null) continue;
      final hit = _projectToNearestWall(
        plan,
        pt.$1 * s,
        pt.$2 * s,
        preferExterior: true,
      );
      if (hit == null) continue;
      final widthCm = _openingWidthCm(
        normWidth: aw.width,
        wallLenCm: hit.len,
        cmPerNorm: s,
        fallback: AppConstants.defaultWindowWidthCm,
        minCm: 60,
        maxCm: 180,
        maxWallFraction: 0.45,
      );
      final half = widthCm / 2;
      final center = hit.centerCm.clamp(half + 5, hit.len - half - 5);
      if (center <= half || center >= hit.len - half) continue;
      if (_overlapsExisting(
        plan.windows.map((w) => (w.wallId, w.centerCm, w.widthCm)),
        hit.wall.id,
        center,
        widthCm,
      )) {
        continue;
      }
      plan.windows.add(
        WindowOpening(
          id: aw.id,
          roomId: _nearestRoomId(plan, hit.wall),
          wallId: hit.wall.id,
          centerCm: center.toDouble(),
          widthCm: widthCm,
          heightCm: AppConstants.defaultWindowHeightCm,
          sillCm: AppConstants.defaultWindowSillCm,
          type: 'normal',
        ),
      );
    }

    if (plan.doors.isEmpty) {
      for (final r in plan.rooms) {
        if (r.type == 'bath') continue;
        final wall = _longestWallTouchingRoom(plan, r) ??
            (plan.walls.isEmpty ? null : plan.walls.first);
        if (wall == null) break;
        final len = _wallLen(wall);
        final w = AppConstants.defaultDoorWidthCm;
        plan.doors.add(
          DoorOpening(
            id: 'door_auto_${r.id}',
            roomId: r.id,
            wallId: wall.id,
            centerCm: len / 2,
            widthCm: w,
            positionType: 'I',
            doorType: 'swing',
          ),
        );
        break;
      }
    }
  }

  /// Y1：优先按「占所在墙比例」算开口宽，图面×比例尺仅作交叉校验。
  static double _openingWidthCm({
    required double normWidth,
    required double wallLenCm,
    required double cmPerNorm,
    required double fallback,
    required double minCm,
    required double maxCm,
    double maxWallFraction = 0.40,
  }) {
    final wallCap = math.max(minCm, wallLenCm * maxWallFraction);
    final hardMax = math.min(maxCm, wallCap);
    if (normWidth <= 0) {
      return fallback.clamp(minCm, hardMax);
    }

    final byWall = wallLenCm * normWidth.clamp(0.0, 0.55);
    final byImage = normWidth * cmPerNorm;

    double raw;
    if (normWidth <= 0.55) {
      if (byWall >= minCm && byWall <= hardMax * 1.15) {
        raw = byWall;
      } else if (byImage >= minCm && byImage <= hardMax * 1.15) {
        raw = byImage;
      } else if (byWall >= minCm * 0.5) {
        raw = byWall;
      } else if (byImage >= minCm * 0.5 && byImage <= maxCm * 1.5) {
        raw = byImage;
      } else {
        raw = fallback;
      }
    } else {
      raw = fallback;
    }
    return raw.clamp(minCm, hardMax);
  }

  static bool _overlapsExisting(
    Iterable<(String?, double, double)> existing,
    String wallId,
    double centerCm,
    double widthCm,
  ) {
    final half = widthCm / 2;
    for (final e in existing) {
      if (e.$1 != wallId) continue;
      final otherHalf = e.$3 / 2;
      if ((e.$2 - centerCm).abs() < half + otherHalf + 15) return true;
    }
    return false;
  }

  /// 解析开口在图面归一化坐标中的中心点。
  static (double, double)? _openingNormPoint({
    required String? wallId,
    required double position,
    required double? cx,
    required double? cy,
    required List<AiWall> aiWalls,
    required List<AiRoom> rooms,
    required bool preferExterior,
  }) {
    if (cx != null && cy != null) {
      return (cx.clamp(0.0, 1.0), cy.clamp(0.0, 1.0));
    }
    if (wallId != null) {
      for (final w in aiWalls) {
        if (w.id != wallId) continue;
        final t = position.clamp(0.05, 0.95);
        return (
          w.x1 + (w.x2 - w.x1) * t,
          w.y1 + (w.y2 - w.y1) * t,
        );
      }
    }
    // 无墙引用：沿 AI 墙或房间边围长取样
    final segs = <(double, double, double, double)>[];
    var walls = aiWalls;
    if (preferExterior) {
      final ext = aiWalls.where((w) => w.kind == 'exterior').toList();
      if (ext.isNotEmpty) walls = ext;
    }
    for (final w in walls) {
      segs.add((w.x1, w.y1, w.x2, w.y2));
    }
    if (segs.isEmpty) {
      for (final r in rooms) {
        final poly = r.polygon;
        if (poly.length < 2) continue;
        for (var i = 0; i < poly.length; i++) {
          final a = poly[i];
          final b = poly[(i + 1) % poly.length];
          segs.add((a[0], a[1], b[0], b[1]));
        }
      }
    }
    if (segs.isEmpty) return null;
    var total = 0.0;
    final lens = <double>[];
    for (final s in segs) {
      final dx = s.$3 - s.$1;
      final dy = s.$4 - s.$2;
      final len = math.sqrt(dx * dx + dy * dy);
      lens.add(len);
      total += len;
    }
    if (total < 1e-6) return null;
    var target = position.clamp(0.02, 0.98) * total;
    for (var i = 0; i < segs.length; i++) {
      final len = lens[i];
      if (target > len && i < segs.length - 1) {
        target -= len;
        continue;
      }
      final t = len <= 1e-9 ? 0.5 : (target / len).clamp(0.05, 0.95);
      final s = segs[i];
      return (s.$1 + (s.$3 - s.$1) * t, s.$2 + (s.$4 - s.$2) * t);
    }
    final last = segs.last;
    return ((last.$1 + last.$3) / 2, (last.$2 + last.$4) / 2);
  }

  static ({WallSeg wall, double centerCm, double len, double dist})?
      _projectToNearestWall(
    PlanDocument plan,
    double xCm,
    double yCm, {
    required bool preferExterior,
  }) {
    var candidates = plan.walls.toList();
    if (preferExterior) {
      final ext = candidates.where((w) => w.kind == 'exterior').toList();
      // 先在外墙上找；若最近点过远再回退全部墙
      if (ext.isNotEmpty) {
        final bestExt = _bestProjection(ext, xCm, yCm);
        if (bestExt != null && bestExt.dist <= 80) return bestExt;
      }
    }
    return _bestProjection(candidates, xCm, yCm);
  }

  static ({WallSeg wall, double centerCm, double len, double dist})?
      _bestProjection(List<WallSeg> walls, double xCm, double yCm) {
    ({WallSeg wall, double centerCm, double len, double dist})? best;
    for (final w in walls) {
      final len = _wallLen(w);
      if (len < 30) continue;
      final dx = w.x2 - w.x1;
      final dy = w.y2 - w.y1;
      final t = ((xCm - w.x1) * dx + (yCm - w.y1) * dy) / (len * len);
      final tc = t.clamp(0.0, 1.0);
      final px = w.x1 + dx * tc;
      final py = w.y1 + dy * tc;
      final dist = math.sqrt((xCm - px) * (xCm - px) + (yCm - py) * (yCm - py));
      if (best == null || dist < best.dist) {
        best = (wall: w, centerCm: tc * len, len: len, dist: dist);
      }
    }
    return best;
  }

  static WallSeg? _longestWallTouchingRoom(PlanDocument plan, RoomRect r) {
    WallSeg? best;
    var bestLen = 0.0;
    for (final w in plan.walls) {
      final mx = (w.x1 + w.x2) / 2;
      final my = (w.y1 + w.y2) / 2;
      if (r.minDistanceToEdges(mx, my) > 25) continue;
      final len = _wallLen(w);
      if (len > bestLen) {
        bestLen = len;
        best = w;
      }
    }
    return best;
  }

  /// 供 UI 在导入前展示清洗效果摘要。
  static FloorplanAiResult withCleanedRooms(FloorplanAiResult r) {
    final cleaned = cleanRooms(r.rooms);
    final snapped = snapAdjacentEdges(cleaned.rooms);
    return FloorplanAiResult(
      imageWidth: r.imageWidth,
      imageHeight: r.imageHeight,
      rooms: snapped,
      walls: r.walls,
      doors: r.doors,
      windows: r.windows,
      source: r.source,
      warnings: [...r.warnings, ...cleaned.warnings],
    );
  }

  static double _wallLen(WallSeg w) {
    final dx = w.x2 - w.x1;
    final dy = w.y2 - w.y1;
    return math.sqrt(dx * dx + dy * dy);
  }

  static String _nearestRoomId(PlanDocument plan, WallSeg wall) {
    final mx = (wall.x1 + wall.x2) / 2;
    final my = (wall.y1 + wall.y2) / 2;
    RoomRect? best;
    var bestD = double.infinity;
    for (final r in plan.rooms) {
      final d = r.minDistanceToEdges(mx, my);
      if (d < bestD) {
        bestD = d;
        best = r;
      }
    }
    return best?.id ?? plan.rooms.first.id;
  }
}
