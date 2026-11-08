import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/plan.dart';
import 'demo_plans.dart';

/// I16：常见户型模板（一键生成可微调）
class PlanTemplateMeta {
  const PlanTemplateMeta({
    required this.id,
    required this.name,
    required this.areaHint,
    required this.subtitle,
    required this.builder,
  });

  final String id;
  final String name;
  final String areaHint;
  final String subtitle;
  final PlanDocument Function() builder;
}

abstract final class PlanTemplates {
  static List<PlanTemplateMeta> all() => [
        PlanTemplateMeta(
          id: '1b1l',
          name: '一室一厅',
          areaHint: '约 55㎡',
          subtitle: '客厅 · 卧室 · 厨卫',
          builder: oneBed,
        ),
        PlanTemplateMeta(
          id: '2b1l',
          name: '两室一厅',
          areaHint: '约 78㎡',
          subtitle: '客厅 · 主卧 · 次卧 · 卫',
          builder: DemoPlans.twoBed,
        ),
        PlanTemplateMeta(
          id: '2b2l',
          name: '两室两厅',
          areaHint: '约 95㎡',
          subtitle: '客餐厅 · 双卧 · 厨卫',
          builder: twoBedTwoLiving,
        ),
        PlanTemplateMeta(
          id: '3b1l',
          name: '三室一厅',
          areaHint: '约 110㎡',
          subtitle: '客厅 · 三卧 · 厨卫',
          builder: threeBedOneLiving,
        ),
        PlanTemplateMeta(
          id: '3b2l',
          name: '三室两厅',
          areaHint: '约 128㎡',
          subtitle: '客餐厅 · 三卧 · 双卫',
          builder: threeBedTwoLiving,
        ),
        PlanTemplateMeta(
          id: '4b2l',
          name: '四室两厅',
          areaHint: '约 155㎡',
          subtitle: '客餐厅 · 四卧 · 双卫',
          builder: fourBedTwoLiving,
        ),
        PlanTemplateMeta(
          id: 'duplex_planar',
          name: '复式平面',
          areaHint: '约 120㎡',
          subtitle: '平面示意·非分层3D',
          builder: duplexPlanar,
        ),
        PlanTemplateMeta(
          id: 'loft',
          name: 'LOFT',
          areaHint: '约 65㎡',
          subtitle: '平面示意·非分层3D',
          builder: loft,
        ),
      ];

  static PlanDocument oneBed() {
    final now = DateTime.now().toIso8601String();
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: 'plan_tpl_${const Uuid().v4().substring(0, 6)}',
        name: '模板·一室一厅',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 55,
        roomCount: 2,
        bathroomCount: 1,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'single',
        floorHeightCm: AppConstants.floorHeightCm,
      ),
      walls: [],
      rooms: [
        RoomRect(
          id: 'r_living',
          name: '客厅',
          type: 'living',
          x: 50,
          y: 50,
          widthCm: 360,
          depthCm: 400,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_bed',
          name: '卧室',
          type: 'bedroom',
          x: 410,
          y: 50,
          widthCm: 300,
          depthCm: 320,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          x: 50,
          y: 450,
          widthCm: 200,
          depthCm: 180,
        ),
        RoomRect(
          id: 'r_bath',
          name: '卫生间',
          type: 'bath',
          x: 250,
          y: 450,
          widthCm: 160,
          depthCm: 180,
          hasStorageZone: true,
        ),
      ],
      doors: [],
      windows: [],
    );
    return _finish(plan);
  }

  static PlanDocument twoBedTwoLiving() {
    final now = DateTime.now().toIso8601String();
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: 'plan_tpl_${const Uuid().v4().substring(0, 6)}',
        name: '模板·两室两厅',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 95,
        roomCount: 4,
        bathroomCount: 1,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'newlywed',
        floorHeightCm: AppConstants.floorHeightCm,
      ),
      walls: [],
      rooms: [
        RoomRect(
          id: 'r_living',
          name: '客厅',
          type: 'living',
          x: 50,
          y: 50,
          widthCm: 420,
          depthCm: 380,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_dining',
          name: '餐厅',
          type: 'dining',
          x: 470,
          y: 50,
          widthCm: 280,
          depthCm: 280,
        ),
        RoomRect(
          id: 'r_master',
          name: '主卧',
          type: 'bedroom_master',
          x: 50,
          y: 430,
          widthCm: 360,
          depthCm: 320,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          x: 410,
          y: 430,
          widthCm: 280,
          depthCm: 280,
        ),
        RoomRect(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          x: 750,
          y: 50,
          widthCm: 200,
          depthCm: 220,
        ),
        RoomRect(
          id: 'r_bath',
          name: '卫生间',
          type: 'bath',
          x: 750,
          y: 270,
          widthCm: 180,
          depthCm: 180,
          hasStorageZone: true,
        ),
      ],
      doors: [],
      windows: [],
    );
    return _finish(plan);
  }

  static PlanDocument threeBedOneLiving() {
    final now = DateTime.now().toIso8601String();
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: 'plan_tpl_${const Uuid().v4().substring(0, 6)}',
        name: '模板·三室一厅',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 110,
        roomCount: 4,
        bathroomCount: 1,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'parenting',
        floorHeightCm: AppConstants.floorHeightCm,
      ),
      walls: [],
      rooms: [
        RoomRect(
          id: 'r_living',
          name: '客厅',
          type: 'living',
          x: 50,
          y: 50,
          widthCm: 450,
          depthCm: 400,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_master',
          name: '主卧',
          type: 'bedroom_master',
          x: 500,
          y: 50,
          widthCm: 360,
          depthCm: 340,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          x: 500,
          y: 390,
          widthCm: 280,
          depthCm: 260,
        ),
        RoomRect(
          id: 'r_bed3',
          name: '书房',
          type: 'study',
          x: 50,
          y: 450,
          widthCm: 260,
          depthCm: 240,
        ),
        RoomRect(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          x: 310,
          y: 450,
          widthCm: 190,
          depthCm: 200,
        ),
        RoomRect(
          id: 'r_bath',
          name: '卫生间',
          type: 'bath',
          x: 780,
          y: 390,
          widthCm: 160,
          depthCm: 200,
          hasStorageZone: true,
        ),
      ],
      doors: [],
      windows: [],
    );
    return _finish(plan);
  }

  static PlanDocument threeBedTwoLiving() {
    final now = DateTime.now().toIso8601String();
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: 'plan_tpl_${const Uuid().v4().substring(0, 6)}',
        name: '模板·三室两厅',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 128,
        roomCount: 5,
        bathroomCount: 2,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'parenting',
        floorHeightCm: AppConstants.floorHeightCm,
      ),
      walls: [],
      rooms: [
        RoomRect(
          id: 'r_living',
          name: '客厅',
          type: 'living',
          x: 50,
          y: 50,
          widthCm: 480,
          depthCm: 400,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_dining',
          name: '餐厅',
          type: 'dining',
          x: 530,
          y: 50,
          widthCm: 300,
          depthCm: 280,
        ),
        RoomRect(
          id: 'r_master',
          name: '主卧',
          type: 'bedroom_master',
          x: 50,
          y: 450,
          widthCm: 380,
          depthCm: 340,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          x: 430,
          y: 450,
          widthCm: 280,
          depthCm: 280,
        ),
        RoomRect(
          id: 'r_bed3',
          name: '次卧2',
          type: 'bedroom',
          x: 710,
          y: 450,
          widthCm: 260,
          depthCm: 260,
        ),
        RoomRect(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          x: 830,
          y: 50,
          widthCm: 200,
          depthCm: 220,
        ),
        RoomRect(
          id: 'r_bath1',
          name: '卫生间',
          type: 'bath',
          x: 830,
          y: 270,
          widthCm: 160,
          depthCm: 160,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_bath2',
          name: '主卫',
          type: 'bath',
          x: 430,
          y: 730,
          widthCm: 160,
          depthCm: 140,
          hasStorageZone: true,
        ),
      ],
      doors: [],
      windows: [],
    );
    return _finish(plan);
  }

  static PlanDocument fourBedTwoLiving() {
    final plan = threeBedTwoLiving();
    plan.meta
      ..id = 'plan_tpl_${const Uuid().v4().substring(0, 6)}'
      ..name = '模板·四室两厅'
      ..updatedAt = DateTime.now().toIso8601String();
    plan.building.areaBuildM2 = 155;
    plan.building.roomCount = 6;
    final guest = RoomRect(
      id: 'r_bed4',
      name: '客房',
      type: 'bedroom',
      x: 590,
      y: 730,
      widthCm: 240,
      depthCm: 220,
    );
    plan.rooms.add(guest);
    plan.rebuildWallsFromRooms();
    plan.doors.add(
      DoorOpening(
        id: 'door_${const Uuid().v4().substring(0, 6)}',
        roomId: guest.id,
        widthCm: AppConstants.defaultDoorWidthCm,
        positionType: 'I',
        doorType: 'swing',
        centerCm: guest.widthCm / 2,
      ),
    );
    _snapDoors(plan);
    return plan;
  }

  /// M：复式平面示意（同平面标「上层」，非真实分层 3D）
  static PlanDocument duplexPlanar() {
    final now = DateTime.now().toIso8601String();
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: 'plan_tpl_${const Uuid().v4().substring(0, 6)}',
        name: '模板·复式平面',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 120,
        roomCount: 5,
        bathroomCount: 1,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'newlywed',
        floorHeightCm: AppConstants.floorHeightCm,
      ),
      walls: [],
      rooms: [
        // 上层示意区（同 2D 平面上方）
        RoomRect(
          id: 'r_upper_master',
          name: '上层·主卧',
          type: 'bedroom_master',
          x: 50,
          y: 50,
          widthCm: 380,
          depthCm: 320,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_upper_bed2',
          name: '上层·次卧',
          type: 'bedroom',
          x: 430,
          y: 50,
          widthCm: 300,
          depthCm: 280,
        ),
        RoomRect(
          id: 'r_stairs',
          name: '楼梯间',
          type: 'other',
          x: 730,
          y: 50,
          widthCm: 160,
          depthCm: 320,
        ),
        // 下层开放客餐厅
        RoomRect(
          id: 'r_living',
          name: '客厅',
          type: 'living',
          x: 50,
          y: 370,
          widthCm: 480,
          depthCm: 380,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_dining',
          name: '餐厅',
          type: 'dining',
          x: 530,
          y: 370,
          widthCm: 360,
          depthCm: 260,
        ),
        RoomRect(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          x: 530,
          y: 630,
          widthCm: 200,
          depthCm: 200,
        ),
        RoomRect(
          id: 'r_bath',
          name: '卫生间',
          type: 'bath',
          x: 730,
          y: 630,
          widthCm: 160,
          depthCm: 200,
          hasStorageZone: true,
        ),
      ],
      doors: [],
      windows: [],
    );
    return _finish(plan);
  }

  /// M：LOFT 平面示意（挑空卧区同平面标注，非分层 3D）
  static PlanDocument loft() {
    final now = DateTime.now().toIso8601String();
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: 'plan_tpl_${const Uuid().v4().substring(0, 6)}',
        name: '模板·LOFT',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 65,
        roomCount: 3,
        bathroomCount: 1,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'single',
        floorHeightCm: AppConstants.floorHeightCm,
      ),
      walls: [],
      rooms: [
        RoomRect(
          id: 'r_living',
          name: '挑空客厅',
          type: 'living',
          x: 50,
          y: 50,
          widthCm: 420,
          depthCm: 480,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_loft_bed',
          name: '挑空卧区',
          type: 'bedroom',
          x: 470,
          y: 50,
          widthCm: 280,
          depthCm: 260,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_stairs',
          name: '楼梯',
          type: 'other',
          x: 470,
          y: 310,
          widthCm: 80,
          depthCm: 220,
        ),
        RoomRect(
          id: 'r_kit',
          name: '开放厨房',
          type: 'kitchen',
          x: 550,
          y: 310,
          widthCm: 200,
          depthCm: 220,
        ),
        RoomRect(
          id: 'r_bath',
          name: '卫生间',
          type: 'bath',
          x: 470,
          y: 530,
          widthCm: 280,
          depthCm: 180,
          hasStorageZone: true,
        ),
      ],
      doors: [],
      windows: [],
    );
    return _finish(plan);
  }

  static PlanDocument _finish(PlanDocument plan) {
    plan.rebuildWallsFromRooms();
    for (final r in plan.rooms) {
      if (r.type == 'bath') continue;
      if (plan.doors.any((d) => d.roomId == r.id)) continue;
      plan.doors.add(
        DoorOpening(
          id: 'door_${const Uuid().v4().substring(0, 6)}',
          roomId: r.id,
          widthCm: AppConstants.defaultDoorWidthCm,
          positionType: 'I',
          doorType: 'swing',
          centerCm: r.widthCm / 2,
        ),
      );
    }
    _snapDoors(plan);
    _addDefaultWindows(plan);
    return plan;
  }

  static void _snapDoors(PlanDocument plan) {
    for (final door in plan.doors) {
      final rooms = plan.rooms.where((r) => r.id == door.roomId);
      if (rooms.isEmpty || plan.walls.isEmpty) continue;
      final r = rooms.first;
      final cx = r.x + r.widthCm / 2;
      final cy = r.y + r.depthCm / 2;
      WallSeg? best;
      var bestDist = double.infinity;
      for (final w in plan.walls) {
        final mx = (w.x1 + w.x2) / 2;
        final my = (w.y1 + w.y2) / 2;
        final dist = (mx - cx) * (mx - cx) + (my - cy) * (my - cy);
        if (dist < bestDist) {
          bestDist = dist;
          best = w;
        }
      }
      if (best == null) continue;
      door.wallId = best.id;
      final dx = best.x2 - best.x1;
      final dy = best.y2 - best.y1;
      final len = math.sqrt(dx * dx + dy * dy);
      final safe = len <= 0 ? 1.0 : len;
      door.centerCm = (safe / 2).clamp(40.0, safe - 40);
    }
  }

  static void _addDefaultWindows(PlanDocument plan) {
    if (plan.walls.isEmpty) return;
    for (final r in plan.rooms) {
      if (r.type == 'bath' || r.type == 'kitchen') continue;
      if (plan.windows.any((w) => w.roomId == r.id)) continue;
      WallSeg? wall;
      for (final w in plan.walls) {
        final midY = (w.y1 + w.y2) / 2;
        final midX = (w.x1 + w.x2) / 2;
        final onTop =
            (midY - r.y).abs() < 20 && midX >= r.x && midX <= r.x + r.widthCm;
        if (onTop) {
          wall = w;
          break;
        }
      }
      wall ??= plan.walls.isNotEmpty ? plan.walls.first : null;
      if (wall == null) continue;
      final dx = wall.x2 - wall.x1;
      final dy = wall.y2 - wall.y1;
      final len = math.sqrt(dx * dx + dy * dy);
      final safe = len <= 0 ? 1.0 : len;
      plan.windows.add(
        WindowOpening(
          id: 'win_${const Uuid().v4().substring(0, 6)}',
          roomId: r.id,
          wallId: wall.id,
          centerCm: (safe / 2).clamp(80.0, safe - 80),
          widthCm: AppConstants.defaultWindowWidthCm,
        ),
      );
    }
  }
}
