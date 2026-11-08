import 'dart:io';

import '../repositories.dart';
import 'floorplan_models.dart';
import 'local_geometry_assist.dart';
import 'roi_edge_refiner.dart';
import 'vision_api_client.dart';

/// 方案 D 编排：优先视觉 API，失败/未配置则本地几何示意；其后 ROI 精校（期次 Z）。
class FloorplanRecognizeService {
  FloorplanRecognizeService({SettingsRepository? settings})
      : _settings = settings ?? SettingsRepository();

  final SettingsRepository _settings;

  /// [roiNorm]：期次 AA 人工框选外轮廓（归一化多边形）；可选。
  /// [refineRoi]：是否跑期次 Z ROI 精校（默认 true）。
  Future<FloorplanAiResult> recognize(
    File imageFile, {
    List<List<double>>? roiNorm,
    bool refineRoi = true,
  }) async {
    final size = await peekImageSize(imageFile);
    final s = await _settings.load();
    final base = (s['vision_api_base'] as String?)?.trim() ?? '';
    final key = (s['vision_api_key'] as String?)?.trim() ?? '';
    final model = (s['vision_api_model'] as String?)?.trim();

    FloorplanAiResult result;
    if (base.isNotEmpty && key.isNotEmpty) {
      try {
        final client = VisionApiClient(
          baseUrl: base,
          apiKey: key,
          model: (model == null || model.isEmpty) ? 'gpt-4o' : model,
        );
        final r = await client.recognize(
          imageFile: imageFile,
          imageWidth: size.$1,
          imageHeight: size.$2,
          roiNorm: roiNorm,
        );
        if (r.rooms.isEmpty) {
          throw Exception('云端未识别到房间');
        }
        result = FloorplanAiResult(
          imageWidth: r.imageWidth,
          imageHeight: r.imageHeight,
          rooms: r.rooms,
          walls: r.walls,
          doors: r.doors,
          windows: r.windows,
          source: 'vision_api',
          warnings: [
            ...r.warnings,
            '已使用云端视觉识别；请核对比例尺与房间后导入。',
          ],
        );
      } catch (e) {
        final local = LocalGeometryAssist.recognize(
          imageWidth: size.$1,
          imageHeight: size.$2,
        );
        result = FloorplanAiResult(
          imageWidth: local.imageWidth,
          imageHeight: local.imageHeight,
          rooms: local.rooms,
          walls: local.walls,
          doors: local.doors,
          windows: local.windows,
          source: 'local',
          warnings: [
            '云端识别失败，已回退本地几何示意：$e',
            ...local.warnings,
          ],
        );
      }
    } else {
      result = LocalGeometryAssist.recognize(
        imageWidth: size.$1,
        imageHeight: size.$2,
      );
    }

    if (!refineRoi) return result;

    // 期次 Z：仅 ROI 内精校（有人工框则用框；否则房间外包）
    try {
      final bytes = await imageFile.readAsBytes();
      result = await RoiEdgeRefiner.refine(
        result,
        bytes,
        roiNorm: roiNorm,
      );
    } catch (e) {
      result = FloorplanAiResult(
        imageWidth: result.imageWidth,
        imageHeight: result.imageHeight,
        rooms: result.rooms,
        walls: result.walls,
        doors: result.doors,
        windows: result.windows,
        source: result.source,
        warnings: [...result.warnings, 'ROI 精校异常已跳过：$e'],
      );
    }
    return result;
  }
}
