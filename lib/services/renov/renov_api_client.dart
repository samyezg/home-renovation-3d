import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../data/renov_styles.dart';
import 'renov_structure.dart';

class RenovResult {
  RenovResult({
    required this.imageBytes,
    required this.source,
    this.notes = const [],
    this.warnings = const [],
    this.structure,
    this.path = 'B',
  });

  final Uint8List imageBytes;
  /// structure_chat | vision_gen | images_api_fallback | local_inpaint | local_preview
  final String source;
  final List<String> notes;
  final List<String> warnings;
  /// B 路径理解结果（可空；供 UI / 将来 3D hook）
  final RenovStructure? structure;
  /// B = 理解+带图生成；A1 = 带图弱路径；A2 = 无原图文生图；local = 本地色调；local-replace = 局部替换
  final String path;
}

/// P1 实景改造 API（理解 / 生成 / 局部）。
///
/// **与 P0 户型识图关系**：可共用 Base/Key/`vision_api_model` 配置，但 **禁止共用 prompt 模板**。
/// P0 见 `floorplan_recognize/vision_api_client.dart`（俯视平面图 schema）；
/// 本类 `understandStructure` 为透视实景 schema，二者输出字段完全不同。
class RenovApiClient {
  RenovApiClient({
    required this.baseUrl,
    required this.apiKey,
    this.understandModel = 'gpt-4o',
    this.generateModel,
  });

  final String baseUrl;
  final String apiKey;
  /// 理解类模型（出 JSON）
  final String understandModel;
  /// 生成类模型；空则回退 understandModel
  final String? generateModel;

  String get _genModel {
    final g = generateModel?.trim();
    if (g != null && g.isNotEmpty) return g;
    return understandModel;
  }

  /// B1：视觉理解房间结构（不写风格）。
  Future<RenovStructure> understandStructure(Uint8List jpeg) async {
    const prompt = '''
你是室内空间结构分析专家。只分析这张房间实景照片的结构，不要改造、不要生成新图。
只输出严格 JSON（不要其它文字）：
{
  "room_type": "living_room|bedroom|kitchen|bathroom|dining|study|other",
  "summary": "一句话描述空间",
  "walls": [{"name":"back_wall","cx":0.5,"cy":0.35,"desc":"主墙"}],
  "doors": [{"name":"entry","cx":0.15,"cy":0.55,"desc":"门洞"}],
  "windows": [{"name":"win1","cx":0.7,"cy":0.4,"desc":"窗"}],
  "furniture": [{"name":"sofa","cx":0.5,"cy":0.75,"desc":"沙发"}],
  "keep": ["door openings","window positions","camera perspective","wall layout"]
}
坐标为相对整图 0～1（左上原点）。尽量标出门窗中心；家具只列大件。
''';
    final map = await _chatJson(prompt, jpeg, model: understandModel);
    return RenovStructure.fromJson(map);
  }

  /// B 主生成：带原图 + 结构 JSON + 锚点；失败由调用方走 A。
  Future<RenovResult> generateWithStructure({
    required Uint8List jpeg,
    required RenovStyle style,
    required RenovStructure? structure,
    List<List<List<double>>> userAnchors = const [],
    List<List<List<double>>> autoEdges = const [],
    String intensity = 'medium',
  }) async {
    final prompt = _buildGenPrompt(
      style: style,
      structure: structure,
      userAnchors: userAnchors,
      autoEdges: autoEdges,
      intensity: intensity,
      forImageConditioned: true,
    );

    final chat = await _chatImageOrUrl(
      prompt,
      jpeg,
      model: _genModel,
    );
    if (chat == null) {
      throw Exception('B 路径未返回效果图');
    }
    return RenovResult(
      imageBytes: chat.$1,
      source: 'structure_chat',
      notes: [
        '路径 B：结构理解 → 弱约束风格迁移（非强控）',
        '风格：${style.name}',
        if (structure != null && !structure.isEmpty) structure.shortUiLine(),
        ...chat.$2,
      ],
      warnings: [
        ..._warn(userAnchors, autoEdges),
        if (structure == null || structure.isEmpty)
          '结构理解为空：仅依赖描线/自动边缘与模型猜测（弱约束）',
      ],
      structure: structure,
      path: 'B',
    );
  }

  /// 局部替换：当前效果图 + mask（白=改）→ 生成后由调用方做 mask 合成。
  Future<RenovResult> inpaintRegion({
    required Uint8List baseJpeg,
    required Uint8List maskPng,
    required RenovStyle style,
    RenovStructure? structure,
    String intensity = 'medium',
    String userHint = '',
  }) async {
    final prompt = _buildInpaintPrompt(
      style: style,
      structure: structure,
      intensity: intensity,
      userHint: userHint,
    );
    final chat = await _chatImageOrUrl(
      prompt,
      baseJpeg,
      model: _genModel,
      extraImages: [
        (maskPng, 'image/png'),
      ],
    );
    if (chat == null) {
      throw Exception('局部替换未返回效果图');
    }
    return RenovResult(
      imageBytes: chat.$1,
      source: 'local_inpaint',
      notes: [
        '局部替换（弱约束）：涂抹区重绘 + mask 合成保留圈外',
        '风格：${style.name}',
        if (userHint.trim().isNotEmpty) '用户意图：$userHint',
        ...chat.$2,
      ],
      warnings: const [
        '非专用 inpaint 端点：圈内效果依赖模型；边缘可能渗色',
      ],
      structure: structure,
      path: 'local-replace',
    );
  }

  /// A fallback：弱路径——优先仍带原图；再退到纯文生图。
  Future<RenovResult> generateStyleOnlyFallback({
    required Uint8List jpeg,
    required RenovStyle style,
    RenovStructure? structure,
    List<List<List<double>>> userAnchors = const [],
    List<List<List<double>>> autoEdges = const [],
    String intensity = 'medium',
  }) async {
    final prompt = _buildGenPrompt(
      style: style,
      structure: structure,
      userAnchors: userAnchors,
      autoEdges: autoEdges,
      intensity: intensity,
      forImageConditioned: true,
    );

    Object? lastErr;
    try {
      final chat = await _chatImageOrUrl(prompt, jpeg, model: _genModel);
      if (chat != null) {
        return RenovResult(
          imageBytes: chat.$1,
          source: 'vision_gen',
          notes: [
            '路径 A1：image-to-image 弱 prompt（仍基于您的照片）',
            '风格：${style.name}',
            ...chat.$2,
          ],
          warnings: [
            '未走完整 B 路径（A1：带图弱路径）',
            ..._warn(userAnchors, autoEdges),
          ],
          structure: structure,
          path: 'A1',
        );
      }
    } catch (e) {
      lastErr = e;
    }

    // 最弱：文生图（无原图像素条件）
    try {
      final textPrompt = _buildGenPrompt(
        style: style,
        structure: structure,
        userAnchors: userAnchors,
        autoEdges: autoEdges,
        intensity: intensity,
        forImageConditioned: false,
      );
      final gen = await _imagesGenerations(textPrompt, model: _genModel);
      if (gen != null) {
        return RenovResult(
          imageBytes: gen,
          source: 'images_api_fallback',
          notes: [
            '路径 A2：text-to-image（未使用您的照片像素）',
            '风格：${style.name}',
          ],
          warnings: [
            '当前无法基于您的照片改造，以下为 AI 参考效果图，非您家实景',
            'A1 带图生成亦失败${lastErr != null ? '：$lastErr' : ''}',
            ..._warn(userAnchors, autoEdges),
          ],
          structure: structure,
          path: 'A2',
        );
      }
    } catch (e) {
      lastErr = e;
    }

    throw Exception(
      lastErr == null
          ? 'A fallback 亦未返回效果图'
          : 'A fallback 失败：$lastErr',
    );
  }

  static String _buildGenPrompt({
    required RenovStyle style,
    required RenovStructure? structure,
    required List<List<List<double>>> userAnchors,
    required List<List<List<double>>> autoEdges,
    required String intensity,
    required bool forImageConditioned,
  }) {
    final intensityHint = switch (intensity) {
      'light' =>
        'light refresh: mainly colors and materials, keep furniture layout',
      'heavy' =>
        'full redesign: new furniture and finishes, keep architecture',
      _ =>
        'moderate refresh: update furniture finishes and wall/floor materials',
    };
    final structureBlock = (structure != null && !structure.isEmpty)
        ? structure.toPromptBlock()
        : 'SCENE UNDERSTANDING: unavailable; rely on photo + anchors.\n';
    final anchorBlock = _anchorPrompt(userAnchors, autoEdges);
    final head = forImageConditioned
        ? 'You are an interior renovation visual designer. EDIT THIS ROOM PHOTO in-place.'
        : 'You are an interior renovation visual designer. Generate a photorealistic renovated room image matching the description.';

    return '''
$head
Target style: ${style.name} (${style.promptHint}).
$intensityHint

$structureBlock
STRUCTURE ANCHORS (priority: user drawn > auto edges > understanding):
$anchorBlock
- Keep door and window positions, sizes, and wall openings FIXED.
- Keep room geometry and camera perspective; do NOT warp architecture.
- Replace finishes/furniture per style; do not invent a different floor plan.
- Photorealistic, same viewpoint as input${forImageConditioned ? '' : ' (approximate from description)'}.
''';
  }

  static String _buildInpaintPrompt({
    required RenovStyle style,
    required RenovStructure? structure,
    required String intensity,
    required String userHint,
  }) {
    final intensityHint = switch (intensity) {
      'light' => 'light change inside mask only',
      'heavy' => 'strong redesign inside mask only',
      _ => 'moderate change inside mask only',
    };
    final structureBlock = (structure != null && !structure.isEmpty)
        ? structure.toPromptBlock()
        : '';
    final hint = userHint.trim().isEmpty
        ? 'Refresh the masked region to better match the target style.'
        : userHint.trim();
    return '''
You are an interior inpainting assistant. Image 1 is the current renovated room photo.
Image 2 is a MASK: WHITE = edit this region; BLACK = keep unchanged.
Target style: ${style.name} (${style.promptHint}).
User request: $hint
$intensityHint
$structureBlock
Rules:
- ONLY change white-mask pixels; do NOT alter door/window openings outside the mask.
- Keep camera perspective, lighting, and unmasked furniture identical.
- Photorealistic blend at mask edges.
Return an edited full-frame image of the same viewpoint.
''';
  }

  static List<String> warnLines(
    List<List<List<double>>> user,
    List<List<List<double>>> auto,
  ) {
    return [
      if (user.isNotEmpty) '已使用用户描线结构锚点（优先）',
      if (user.isEmpty && auto.isNotEmpty) '未描线：已用自动边缘作弱约束',
      if (user.isEmpty && auto.isEmpty) '无用户描线：依赖理解结果或弱控制',
    ];
  }

  static List<String> _warn(
    List<List<List<double>>> user,
    List<List<List<double>>> auto,
  ) =>
      warnLines(user, auto);

  static String _anchorPrompt(
    List<List<List<double>>> user,
    List<List<List<double>>> auto,
  ) {
    String fmt(List<List<List<double>>> strokes, String label) {
      if (strokes.isEmpty) return '';
      final buf = StringBuffer('$label:\n');
      for (var i = 0; i < strokes.length && i < 12; i++) {
        final s = strokes[i];
        final pts = s
            .take(8)
            .map((p) =>
                '(${p[0].toStringAsFixed(3)},${p[1].toStringAsFixed(3)})')
            .join('→');
        buf.writeln('  stroke$i: $pts');
      }
      return buf.toString();
    }

    if (user.isNotEmpty) {
      return '${fmt(user, "USER-DRAWN wall/floor junction lines (normalized 0-1, must respect)")}\n';
    }
    if (auto.isNotEmpty) {
      return '${fmt(auto, "AUTO-DETECTED soft edges (weak guidance)")}\n';
    }
    return 'No stroke anchors.\n';
  }

  Future<Map<String, dynamic>> _chatJson(
    String prompt,
    Uint8List jpeg, {
    required String model,
  }) async {
    final b64 = base64Encode(jpeg);
    final uri = _completionsUri(baseUrl);
    final body = {
      'model': model,
      'temperature': 0.1,
      'max_tokens': 4096,
      'thinking': {'type': 'disabled'},
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$b64'},
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
        .timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('结构理解 HTTP ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = map['choices'] as List? ?? [];
    if (choices.isEmpty) throw Exception('结构理解无返回');
    final msg = choices.first['message'] as Map<String, dynamic>? ?? {};
    final content = '${msg['content'] ?? ''}';
    final jsonMap = _extractJson(content);
    if (jsonMap.isEmpty) throw Exception('结构理解无法解析 JSON');
    return jsonMap;
  }

  Future<Uint8List?> _imagesGenerations(
    String prompt, {
    required String model,
  }) async {
    final uri = _imagesUri(baseUrl);
    final body = {
      'model': model,
      'prompt': prompt,
      'n': 1,
      'size': '1024x1024',
      'response_format': 'b64_json',
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
        .timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as List? ?? [];
    if (data.isEmpty) return null;
    final first = data.first as Map<String, dynamic>;
    final b64 = first['b64_json'] as String?;
    if (b64 != null && b64.isNotEmpty) return base64Decode(b64);
    final url = first['url'] as String?;
    if (url != null && url.isNotEmpty) {
      final imgRes =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (imgRes.statusCode >= 200 && imgRes.statusCode < 300) {
        return imgRes.bodyBytes;
      }
    }
    return null;
  }

  Future<(Uint8List, List<String>)?> _chatImageOrUrl(
    String prompt,
    Uint8List jpeg, {
    required String model,
    List<(Uint8List bytes, String mime)> extraImages = const [],
  }) async {
    final b64 = base64Encode(jpeg);
    final uri = _completionsUri(baseUrl);
    final contentParts = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '''
$prompt

Image 1 = room photo. Additional images (if any) = MASK (white=edit, black=keep) unless noted in the prompt.

If you can edit/generate an image, return STRICT JSON only:
{"image_base64":"<png_or_jpeg_base64>"}
OR {"image_url":"https://..."}
OR if you cannot output an image, return:
{"notes":["..."],"prompt_en":"detailed English image prompt"}
''',
      },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$b64'},
      },
      for (final e in extraImages)
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:${e.$2};base64,${base64Encode(e.$1)}',
          },
        },
    ];
    final body = {
      'model': model,
      'temperature': 0.4,
      'max_tokens': 4096,
      'thinking': {'type': 'disabled'},
      'messages': [
        {'role': 'user', 'content': contentParts},
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
      throw Exception('改造接口 HTTP ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = map['choices'] as List? ?? [];
    if (choices.isEmpty) return null;
    final msg = choices.first['message'] as Map<String, dynamic>? ?? {};
    final textContent = '${msg['content'] ?? ''}';

    final contentList = msg['content'];
    if (contentList is List) {
      for (final part in contentList) {
        if (part is! Map) continue;
        final imgUrl = part['image_url'];
        if (imgUrl is Map && imgUrl['url'] is String) {
          final u = imgUrl['url'] as String;
          if (u.startsWith('data:image')) {
            final i = u.indexOf('base64,');
            if (i > 0) {
              return (base64Decode(u.substring(i + 7)), const <String>[]);
            }
          } else if (u.startsWith('http')) {
            final r = await http.get(Uri.parse(u));
            if (r.statusCode >= 200 && r.statusCode < 300) {
              return (r.bodyBytes, const <String>[]);
            }
          }
        }
      }
    }

    final jsonMap = _extractJson(textContent);
    final ib64 = jsonMap['image_base64'] as String?;
    if (ib64 != null && ib64.isNotEmpty) {
      return (base64Decode(ib64), const <String>[]);
    }
    final iurl = jsonMap['image_url'] as String?;
    if (iurl != null && iurl.startsWith('http')) {
      final r = await http.get(Uri.parse(iurl));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return (r.bodyBytes, const <String>[]);
      }
    }

    final notes = (jsonMap['notes'] as List?)?.map((e) => '$e').toList() ??
        const <String>[];
    final promptEn = jsonMap['prompt_en'] as String?;
    if (promptEn != null && promptEn.trim().isNotEmpty) {
      final gen = await _imagesGenerations(promptEn, model: model);
      if (gen != null) return (gen, notes);
    }
    if (notes.isNotEmpty) {
      throw Exception('模型仅返回文字建议，当前端点不支持出图');
    }
    return null;
  }

  static Uri _completionsUri(String baseUrl) {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/chat/completions')) return Uri.parse(root);
    if (RegExp(r'/v\d+$').hasMatch(root)) {
      return Uri.parse('$root/chat/completions');
    }
    return Uri.parse('$root/v1/chat/completions');
  }

  static Uri _imagesUri(String baseUrl) {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/images/generations')) return Uri.parse(root);
    if (root.endsWith('/chat/completions')) {
      root = root.substring(0, root.length - '/chat/completions'.length);
    }
    if (RegExp(r'/v\d+$').hasMatch(root)) {
      return Uri.parse('$root/images/generations');
    }
    return Uri.parse('$root/v1/images/generations');
  }

  static Map<String, dynamic> _extractJson(String content) {
    var t = content.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start < 0 || end <= start) return {};
    try {
      return jsonDecode(t.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Uint8List downscaleJpeg(List<int> bytes, {required int maxSide}) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return Uint8List.fromList(bytes);
      final m = decoded.width > decoded.height ? decoded.width : decoded.height;
      final resized = m <= maxSide
          ? decoded
          : img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxSide : null,
              height: decoded.height > decoded.width ? maxSide : null,
            );
      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (_) {
      return Uint8List.fromList(bytes);
    }
  }
}
