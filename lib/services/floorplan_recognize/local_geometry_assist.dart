import 'floorplan_models.dart';

/// 方案 D 本地几何半程：按图片纵横比生成可编辑正交户型示意（0～1 坐标）。
/// 无云端时保证「拍照→比例尺→进画布」闭环；标注为本地示意，可继续手改。
class LocalGeometryAssist {
  LocalGeometryAssist._();

  static FloorplanAiResult recognize({
    required int imageWidth,
    required int imageHeight,
  }) {
    final w = imageWidth <= 0 ? 1000 : imageWidth;
    final h = imageHeight <= 0 ? 1000 : imageHeight;
    final aspect = w / h;
    final warnings = <String>[
      '当前为本地几何示意（方案 D 离线半程），非云端精识别。',
      '请设置比例尺后导入，并在画布用切角/顶点精修成自家户型。',
    ];

    late List<AiRoom> rooms;
    late List<AiDoor> doors;
    late List<AiWindow> windows;

    if (aspect >= 1.25) {
      // 横厅：左客厅 + 右两卧 + 下厨卫
      rooms = [
        AiRoom(
          id: 'r_living',
          name: '客厅',
          type: 'living_room',
          polygon: [
            [0.08, 0.12],
            [0.52, 0.12],
            [0.52, 0.62],
            [0.08, 0.62],
          ],
        ),
        AiRoom(
          id: 'r_bed1',
          name: '主卧',
          type: 'bedroom',
          polygon: [
            [0.52, 0.12],
            [0.92, 0.12],
            [0.92, 0.42],
            [0.52, 0.42],
          ],
        ),
        AiRoom(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          polygon: [
            [0.52, 0.42],
            [0.92, 0.42],
            [0.92, 0.72],
            [0.52, 0.72],
          ],
        ),
        AiRoom(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          polygon: [
            [0.08, 0.62],
            [0.32, 0.62],
            [0.32, 0.88],
            [0.08, 0.88],
          ],
        ),
        AiRoom(
          id: 'r_bath',
          name: '卫生间',
          type: 'bathroom',
          polygon: [
            [0.32, 0.62],
            [0.52, 0.62],
            [0.52, 0.88],
            [0.32, 0.88],
          ],
        ),
      ];
      doors = [
        AiDoor(id: 'd1', position: 0.45, width: 0.04),
        AiDoor(id: 'd2', position: 0.55, width: 0.04),
      ];
      windows = [
        AiWindow(id: 'win1', position: 0.3, width: 0.1),
        AiWindow(id: 'win2', position: 0.7, width: 0.08),
      ];
    } else if (aspect <= 0.85) {
      // 竖向：上客厅下两卧
      rooms = [
        AiRoom(
          id: 'r_living',
          name: '客厅',
          type: 'living_room',
          polygon: [
            [0.12, 0.08],
            [0.88, 0.08],
            [0.88, 0.42],
            [0.12, 0.42],
          ],
        ),
        AiRoom(
          id: 'r_bed1',
          name: '主卧',
          type: 'bedroom',
          polygon: [
            [0.12, 0.42],
            [0.52, 0.42],
            [0.52, 0.78],
            [0.12, 0.78],
          ],
        ),
        AiRoom(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          polygon: [
            [0.52, 0.42],
            [0.88, 0.42],
            [0.88, 0.78],
            [0.52, 0.78],
          ],
        ),
        AiRoom(
          id: 'r_bath',
          name: '卫生间',
          type: 'bathroom',
          polygon: [
            [0.12, 0.78],
            [0.40, 0.78],
            [0.40, 0.92],
            [0.12, 0.92],
          ],
        ),
        AiRoom(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          polygon: [
            [0.40, 0.78],
            [0.88, 0.78],
            [0.88, 0.92],
            [0.40, 0.92],
          ],
        ),
      ];
      doors = [AiDoor(id: 'd1', position: 0.5, width: 0.04)];
      windows = [AiWindow(id: 'win1', position: 0.4, width: 0.1)];
    } else {
      // 近方：经典两室一厅示意
      rooms = [
        AiRoom(
          id: 'r_living',
          name: '客厅',
          type: 'living_room',
          polygon: [
            [0.10, 0.12],
            [0.58, 0.12],
            [0.58, 0.58],
            [0.10, 0.58],
          ],
        ),
        AiRoom(
          id: 'r_bed1',
          name: '主卧',
          type: 'bedroom',
          polygon: [
            [0.58, 0.12],
            [0.90, 0.12],
            [0.90, 0.48],
            [0.58, 0.48],
          ],
        ),
        AiRoom(
          id: 'r_bed2',
          name: '次卧',
          type: 'bedroom',
          polygon: [
            [0.58, 0.48],
            [0.90, 0.48],
            [0.90, 0.78],
            [0.58, 0.78],
          ],
        ),
        AiRoom(
          id: 'r_kit',
          name: '厨房',
          type: 'kitchen',
          polygon: [
            [0.10, 0.58],
            [0.34, 0.58],
            [0.34, 0.88],
            [0.10, 0.88],
          ],
        ),
        AiRoom(
          id: 'r_bath',
          name: '卫生间',
          type: 'bathroom',
          polygon: [
            [0.34, 0.58],
            [0.58, 0.58],
            [0.58, 0.88],
            [0.34, 0.88],
          ],
        ),
      ];
      doors = [
        AiDoor(id: 'd1', position: 0.4, width: 0.04),
        AiDoor(id: 'd2', position: 0.6, width: 0.04),
      ];
      windows = [
        AiWindow(id: 'win1', position: 0.25, width: 0.09),
        AiWindow(id: 'win2', position: 0.75, width: 0.08),
      ];
    }

    return FloorplanAiResult(
      imageWidth: w,
      imageHeight: h,
      rooms: rooms,
      doors: doors,
      windows: windows,
      source: 'local',
      warnings: warnings,
    );
  }
}
