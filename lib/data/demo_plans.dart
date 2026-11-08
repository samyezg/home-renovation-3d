import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/plan.dart';

/// 示例方案（Schema 对齐 docs/03-v1 完整示例，略简）
abstract final class DemoPlans {
  static PlanDocument twoBed() {
    final now = DateTime.now().toIso8601String();
    final id = 'plan_demo_${const Uuid().v4().substring(0, 6)}';
    final plan = PlanDocument(
      schemaVersion: 1,
      meta: PlanMeta(
        id: id,
        name: '示例·两室一厅',
        createdAt: now,
        updatedAt: now,
      ),
      building: BuildingInfo(
        areaBuildM2: 78,
        areaNetM2: 62,
        floorHeightCm: AppConstants.floorHeightCm,
        roomCount: 3,
        bathroomCount: 1,
        cityName: '成都',
        cityTier: 'new_tier1',
        cityTierSource: 'auto',
        familyStage: 'newlywed',
        residents: 2,
        storageRatioSurvey: 0.09,
        storageIntegrated: false,
        displayRatioOk: false,
        colorSchemeOk: false,
      ),
      walls: [
        WallSeg(id: 'w1', x1: 50, y1: 50, x2: 850, y2: 50, kind: 'exterior'),
        WallSeg(id: 'w2', x1: 850, y1: 50, x2: 850, y2: 650, kind: 'exterior'),
        WallSeg(id: 'w3', x1: 850, y1: 650, x2: 50, y2: 650, kind: 'exterior'),
        WallSeg(id: 'w4', x1: 50, y1: 650, x2: 50, y2: 50, kind: 'exterior'),
        WallSeg(id: 'w5', x1: 450, y1: 50, x2: 450, y2: 400, kind: 'partition'),
      ],
      rooms: [
        RoomRect(
          id: 'r_living',
          name: '客厅',
          type: 'living',
          x: 50,
          y: 50,
          widthCm: 400,
          depthCm: 450,
          hasStorageZone: true,
        ),
        RoomRect(
          id: 'r_master',
          name: '主卧',
          type: 'bedroom_master',
          x: 450,
          y: 50,
          widthCm: 400,
          depthCm: 350,
          hasStorageZone: false,
        ),
        RoomRect(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          x: 450,
          y: 400,
          widthCm: 280,
          depthCm: 250,
          hasStorageZone: false,
        ),
        RoomRect(
          id: 'r_bath',
          name: '卫生间',
          type: 'bath',
          x: 50,
          y: 500,
          widthCm: 200,
          depthCm: 150,
          hasStorageZone: true,
        ),
      ],
      doors: [
        DoorOpening(
          id: 'd_living',
          roomId: 'r_living',
          wallId: 'w5',
          centerCm: 200,
          widthCm: 80,
          positionType: 'I',
        ),
        DoorOpening(
          id: 'd_master',
          roomId: 'r_master',
          wallId: 'w5',
          centerCm: 120,
          widthCm: 80,
          positionType: 'II',
        ),
        DoorOpening(
          id: 'd_bed2',
          roomId: 'r_bed2',
          wallId: 'w5',
          centerCm: 80,
          widthCm: 80,
          positionType: 'O',
        ),
      ],
      windows: [
        WindowOpening(
          id: 'win_living_n',
          roomId: 'r_living',
          wallId: 'w1',
          centerCm: 200,
          widthCm: 180,
          heightCm: 140,
          sillCm: 90,
          type: 'normal',
        ),
        WindowOpening(
          id: 'win_master_n',
          roomId: 'r_master',
          wallId: 'w1',
          centerCm: 600,
          widthCm: 150,
          heightCm: 210,
          sillCm: 0,
          type: 'floor',
        ),
        WindowOpening(
          id: 'win_living_w',
          roomId: 'r_living',
          wallId: 'w4',
          centerCm: 375,
          widthCm: 150,
          heightCm: 140,
          sillCm: 45,
          type: 'bay',
        ),
      ],
      constraints: [
        ConstraintMark(
          id: 'c_lb',
          type: 'load_bearing',
          wallId: 'w2',
          note: '示例：外墙承重标记',
        ),
      ],
      furniture: [
        // 客厅中心偏下：沙发
        FurnitureItem(
          id: 'furn_demo_sofa',
          type: 'furn_sofa',
          roomId: 'r_living',
          x: 250,
          y: 320,
          rotation: 0,
          widthCm: 200,
          depthCm: 90,
          heightCm: 80,
        ),
        // 主卧中心：床
        FurnitureItem(
          id: 'furn_demo_bed',
          type: 'furn_bed',
          roomId: 'r_master',
          x: 650,
          y: 225,
          rotation: 0,
          widthCm: 150,
          depthCm: 200,
          heightCm: 50,
        ),
      ],
      annotations: Annotations(
        redRulerCm: 320,
        blueRulerCm: null,
        openConnections: ['living-balcony'],
      ),
    );
    return plan;
  }
}
