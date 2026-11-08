import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'floorplan_models.dart';
import 'roi_geom.dart';

/// 可选：OpenAI 兼容多模态接口（方案 D 云端语义半程 · **P0 户型俯视识图**）。
///
/// 与 P1 `RenovApiClient` **共用** settings 中的 Base/Key/理解模型名，但 **本文件 `_prompt` 仅用于户型图**，
/// 不得与实景改造 `understandStructure` prompt 混用。
class VisionApiClient {
  VisionApiClient({
    required this.baseUrl,
    required this.apiKey,
    this.model = 'gpt-4o',
  });

  final String baseUrl;
  final String apiKey;
  final String model;

  static const _prompt = '''
你是一个专业的建筑图纸识别专家。请分析这张户型图，识别墙体、门窗和房间，并只输出严格 JSON（不要其它文字）。

坐标使用相对比例 0-1（x 横向，y 纵向，原点在左上）。

输出格式：
{
  "walls": [{"id":"w1","x1":0.1,"y1":0.1,"x2":0.5,"y2":0.1,"type":"exterior"}],
  "doors": [{"id":"d1","wall_id":"w1","position":0.3,"width":0.05,"cx":0.22,"cy":0.10,"swing":"left"}],
  "windows": [{"id":"win1","wall_id":"w1","position":0.5,"width":0.08,"cx":0.30,"cy":0.10}],
  "rooms": [{"id":"r1","name":"客厅","type":"living_room","polygon":[[0.1,0.1],[0.5,0.1],[0.5,0.4],[0.1,0.4]]}]
}

要求：walls 的 id 必须与门窗 wall_id 对应；门窗尽量同时给出 cx/cy（开口中心）；width 为图面归一化宽度。
type 可用：living_room/bedroom/kitchen/bathroom/balcony/dining/entry/study/other
''';

  Future<FloorplanAiResult> recognize({
    required File imageFile,
    required int imageWidth,
    required int imageHeight,
    List<List<double>>? roiNorm,
  }) async {
    final fullBytes = await imageFile.readAsBytes();
    Uint8List sendBytes = fullBytes;
    var prompt = _prompt;
    RoiCrop? cropNorm;
    var coordsOnCrop = false;

    if (roiNorm != null && roiNorm.length >= 3) {
      final cropped = RoiGeom.cropToJpeg(fullBytes, roiNorm);
      if (cropped != null) {
        sendBytes = cropped.bytes;
        cropNorm = cropped.cropNorm;
        coordsOnCrop = true;
        prompt += RoiGeom.promptSnippetCropped();
      } else {
        prompt += RoiGeom.promptSnippetFullImage(roiNorm);
      }
    }

    final b64 = base64Encode(sendBytes);
    final uri = _completionsUri(baseUrl);
    final body = {
      'model': model,
      'temperature': 0.1,
      'max_tokens': 8192,
      // 豆包 Seed 默认开启思考，户型 JSON 易超时；关闭后视觉任务通常数秒级。
      'thinking': {'type': 'disabled'},
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$b64',
              },
            },
          ],
        },
      ],
    };
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 150));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('识图接口 HTTP ${res.statusCode}: ${res.body}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = map['choices'] as List? ?? [];
    if (choices.isEmpty) throw Exception('识图接口无返回 choices');
    final msg = choices.first['message'] as Map<String, dynamic>? ?? {};
    final content = '${msg['content'] ?? ''}';
    final jsonMap = _extractJson(content);
    jsonMap['image_size'] = {'width': imageWidth, 'height': imageHeight};
    jsonMap['source'] = 'vision_api';
    var result = FloorplanAiResult.fromJson(jsonMap);
    if (coordsOnCrop && cropNorm != null) {
      result = _mapResultFromCrop(result, cropNorm, imageWidth, imageHeight);
    }
    if (roiNorm != null && roiNorm.length >= 3) {
      result = FloorplanAiResult(
        imageWidth: result.imageWidth,
        imageHeight: result.imageHeight,
        rooms: result.rooms,
        walls: result.walls,
        doors: result.doors,
        windows: result.windows,
        source: result.source,
        warnings: [...result.warnings, '已使用人工 ROI 框选辅助识别'],
      );
    }
    return result;
  }

  static FloorplanAiResult _mapResultFromCrop(
    FloorplanAiResult r,
    RoiCrop crop,
    int fullW,
    int fullH,
  ) {
    List<List<double>> mapPoly(List<List<double>> poly) =>
        RoiGeom.mapPolyFromCrop(poly, crop);

    return FloorplanAiResult(
      imageWidth: fullW,
      imageHeight: fullH,
      rooms: [
        for (final room in r.rooms)
          AiRoom(
            id: room.id,
            name: room.name,
            type: room.type,
            polygon: mapPoly(room.polygon),
          ),
      ],
      walls: [
        for (final w in r.walls)
          AiWall(
            id: w.id,
            x1: RoiGeom.mapXFromCrop(w.x1, crop),
            y1: RoiGeom.mapYFromCrop(w.y1, crop),
            x2: RoiGeom.mapXFromCrop(w.x2, crop),
            y2: RoiGeom.mapYFromCrop(w.y2, crop),
            kind: w.kind,
          ),
      ],
      doors: [
        for (final d in r.doors)
          AiDoor(
            id: d.id,
            wallId: d.wallId,
            position: d.position,
            width: d.width * crop.width, // 归一化宽度相对整图缩小
            cx: d.cx == null ? null : RoiGeom.mapXFromCrop(d.cx!, crop),
            cy: d.cy == null ? null : RoiGeom.mapYFromCrop(d.cy!, crop),
          ),
      ],
      windows: [
        for (final w in r.windows)
          AiWindow(
            id: w.id,
            wallId: w.wallId,
            position: w.position,
            width: w.width * crop.width,
            cx: w.cx == null ? null : RoiGeom.mapXFromCrop(w.cx!, crop),
            cy: w.cy == null ? null : RoiGeom.mapYFromCrop(w.cy!, crop),
          ),
      ],
      source: r.source,
      warnings: r.warnings,
    );
  }

  /// 兼容三种填法：
  /// - OpenAI：`https://api.openai.com` → `/v1/chat/completions`
  /// - 方舟等：`https://ark.../api/v3` → `/chat/completions`
  /// - 已填完整：`.../chat/completions` → 原样使用（避免二次拼接）
  static Uri _completionsUri(String baseUrl) {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/chat/completions')) {
      return Uri.parse(root);
    }
    if (RegExp(r'/v\d+$').hasMatch(root)) {
      return Uri.parse('$root/chat/completions');
    }
    return Uri.parse('$root/v1/chat/completions');
  }

  Map<String, dynamic> _extractJson(String content) {
    var t = content.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw Exception('无法从模型输出解析 JSON');
    }
    var slice = t.substring(start, end + 1);
    try {
      return jsonDecode(slice) as Map<String, dynamic>;
    } catch (_) {
      // 模型偶发截断/尾逗号：尽量修到可解析
      slice = slice.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
      try {
        return jsonDecode(slice) as Map<String, dynamic>;
      } catch (_) {
        final repaired = _repairTruncatedJson(slice);
        return jsonDecode(repaired) as Map<String, dynamic>;
      }
    }
  }

  /// 截断时丢掉最后一个不完整对象，闭合数组/对象。
  static String _repairTruncatedJson(String raw) {
    var s = raw.trim();
    // 从末尾回退到最近一个完整 `}` 或 `]` 边界后的逗号处裁掉残片
    final lastObj = s.lastIndexOf('}');
    if (lastObj > 0) {
      s = s.substring(0, lastObj + 1);
    }
    s = s.replaceAll(RegExp(r',\s*$'), '');
    // 补齐未闭合括号
    var brace = 0;
    var bracket = 0;
    for (final c in s.codeUnits) {
      if (c == 0x7B) brace++;
      if (c == 0x7D) brace--;
      if (c == 0x5B) bracket++;
      if (c == 0x5D) bracket--;
    }
    while (bracket > 0) {
      s += ']';
      bracket--;
    }
    while (brace > 0) {
      s += '}';
      brace--;
    }
    s = s.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    return s;
  }
}

/// 读取图片宽高（JPEG/PNG 粗解析；失败则默认 1000）。
Future<(int, int)> peekImageSize(File file) async {
  try {
    final bytes = await file.openRead(0, 64).fold<List<int>>(
      <int>[],
      (p, e) => p..addAll(e),
    );
    final bd = Uint8List.fromList(bytes);
    // PNG
    if (bd.length >= 24 &&
        bd[0] == 0x89 &&
        bd[1] == 0x50 &&
        bd[2] == 0x4E &&
        bd[3] == 0x47) {
      final w = (bd[16] << 24) | (bd[17] << 16) | (bd[18] << 8) | bd[19];
      final h = (bd[20] << 24) | (bd[21] << 16) | (bd[22] << 8) | bd[23];
      return (w, h);
    }
    // JPEG SOF
    if (bd.length >= 2 && bd[0] == 0xFF && bd[1] == 0xD8) {
      final all = await file.readAsBytes();
      var i = 2;
      while (i < all.length - 9) {
        if (all[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = all[i + 1];
        if (marker == 0xC0 || marker == 0xC2) {
          final h = (all[i + 5] << 8) | all[i + 6];
          final w = (all[i + 7] << 8) | all[i + 8];
          return (w, h);
        }
        if (marker == 0xD9) break;
        final len = (all[i + 2] << 8) | all[i + 3];
        i += 2 + len;
      }
    }
  } catch (_) {}
  return (1000, 1000);
}
