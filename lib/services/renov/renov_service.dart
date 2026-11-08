import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../data/renov_styles.dart';
import '../../widgets/structure_anchor_editor.dart';
import '../repositories.dart';
import 'renov_api_client.dart';
import 'renov_mask.dart';
import 'renov_structure.dart';

/// 单次选图会话内云端整图生成达到软上限（不含局部替换）。
///
/// 口径：按**同一实景图指纹**累计（非按天）；「确认继续」只放行**下一次**生成。
class RenovSoftLimitException implements Exception {
  RenovSoftLimitException({required this.count, required this.limit});

  final int count;
  final int limit;

  @override
  String toString() =>
      '同一张实景图已云端生成 $count 次（软上限 $limit，按图累计、非按天）。'
      '确认后仅放行下一次；之后再次超限仍会提示。';
}

/// P1 编排：默认 B（理解→带结构生成）；A1/A2 / 本地色调为 fallback。
///
/// 成本：`understandStructure` **按当前流程会话挂载**（同图换风格不重复调用；离开流程页清除）；
/// 整图生成软上限按图指纹累计。
class RenovService {
  RenovService({SettingsRepository? settings})
      : _settings = settings ?? SettingsRepository();

  final SettingsRepository _settings;

  /// 同一实景图云端整图生成软上限（含 B/A1/A2；不含局部替换）。
  static const int softGenerateLimit = 5;

  static _UnderstandCacheEntry? _understandCache;
  static final Map<int, int> _generateCounts = {};

  /// 换图时清零该图生成计数。
  static void resetSessionForFingerprint(int fingerprint) {
    _generateCounts.remove(fingerprint);
    final c = _understandCache;
    if (c != null && c.fingerprint == fingerprint) {
      _understandCache = null;
    }
  }

  /// 离开「拍照改造」流程页时调用：清理解缓存 + 全部生成计数。
  static void endFlowSession() {
    _understandCache = null;
    _generateCounts.clear();
  }

  static void clearUnderstandCache() => _understandCache = null;

  Future<RenovResult> generate({
    required File imageFile,
    required RenovStyle style,
    List<List<List<double>>> userAnchors = const [],
    bool useAutoEdge = true,
    String intensity = 'medium',
    bool acknowledgeSoftLimit = false,
  }) async {
    var auto = <List<List<double>>>[];
    if (userAnchors.isEmpty && useAutoEdge) {
      final bytes = await imageFile.readAsBytes();
      auto = await AutoEdgeHints.extract(bytes);
    }

    final s = await _settings.load();
    final base = (s['vision_api_base'] as String?)?.trim() ?? '';
    final key = (s['vision_api_key'] as String?)?.trim() ?? '';
    final understandModel = (s['vision_api_model'] as String?)?.trim();
    final genModel = (s['vision_gen_model'] as String?)?.trim();

    final raw = await imageFile.readAsBytes();
    final jpeg = RenovApiClient.downscaleJpeg(raw, maxSide: 1280);
    final fp = fingerprintJpeg(jpeg);

    if (base.isEmpty || key.isEmpty) {
      return _local(
        imageFile,
        style,
        userAnchors,
        auto,
        note: '未配置视觉 API：仅本地色调/材质示意，不是 AI 改造图。真实效果以云端生成为准。',
      );
    }

    final used = _generateCounts[fp] ?? 0;
    if (!acknowledgeSoftLimit && used >= softGenerateLimit) {
      throw RenovSoftLimitException(count: used, limit: softGenerateLimit);
    }

    final client = RenovApiClient(
      baseUrl: base,
      apiKey: key,
      understandModel:
          (understandModel == null || understandModel.isEmpty)
              ? 'gpt-4o'
              : understandModel,
      generateModel: (genModel == null || genModel.isEmpty) ? null : genModel,
    );

    RenovStructure? structure;
    String? understandErr;
    var understandFromCache = false;
    try {
      final cached = _readUnderstandCache(fp);
      if (cached != null) {
        structure = cached;
        understandFromCache = true;
      } else {
        structure = await client.understandStructure(jpeg);
        _writeUnderstandCache(fp, structure);
      }
    } catch (e) {
      understandErr = '$e';
      structure = null;
    }

    // B 主路径：有无结构都先尝试「带图 + 结构/锚点」生成
    try {
      final b = await client.generateWithStructure(
        jpeg: jpeg,
        style: style,
        structure: structure,
        userAnchors: userAnchors,
        autoEdges: auto,
        intensity: intensity,
      );
      _bumpGenerateCount(fp);
      final cacheNote = understandFromCache
          ? '结构理解：会话缓存命中（未重复调用 understand）'
          : '结构理解：本次新调用';
      if (understandErr != null) {
        return RenovResult(
          imageBytes: b.imageBytes,
          source: b.source,
          notes: [cacheNote, ...b.notes],
          warnings: [
            '结构理解失败，已降级半 B（仅描线/边缘+带图生成）：$understandErr',
            ...b.warnings,
          ],
          structure: b.structure,
          path: structure == null ? 'B-lite' : 'B',
        );
      }
      return RenovResult(
        imageBytes: b.imageBytes,
        source: b.source,
        notes: [cacheNote, ...b.notes],
        warnings: b.warnings,
        structure: b.structure,
        path: b.path,
      );
    } catch (bErr) {
      // A fallback：先 i2i 弱 prompt，再无原图像素 t2i
      try {
        final a = await client.generateStyleOnlyFallback(
          jpeg: jpeg,
          style: style,
          structure: structure,
          userAnchors: userAnchors,
          autoEdges: auto,
          intensity: intensity,
        );
        _bumpGenerateCount(fp);
        return RenovResult(
          imageBytes: a.imageBytes,
          source: a.source,
          notes: [
            understandFromCache
                ? '结构理解：会话缓存命中（未重复调用 understand）'
                : '结构理解：本次新调用或失败',
            ...a.notes,
          ],
          warnings: [
            'B 生成失败，已走 A fallback（先 A1 带图，再必要时 A2 文生图）：$bErr',
            if (understandErr != null) '结构理解：$understandErr',
            ...a.warnings,
          ],
          structure: a.structure ?? structure,
          path: a.path,
        );
      } catch (aErr) {
        return _local(
          imageFile,
          style,
          userAnchors,
          auto,
          structure: structure,
          note: '云端 B/A 均失败，已回落本地色调示意（不是 AI 改造图）。真实效果以云端为准。',
          extraWarnings: [
            'B 失败：$bErr',
            'A 失败：$aErr',
            if (understandErr != null) '结构理解：$understandErr',
          ],
        );
      }
    }
  }

  /// P1.x：局部替换。圈外由 mask 合成强制保留；无 API / 失败时 mask 内本地色调示意。
  Future<RenovResult> inpaintLocal({
    required Uint8List baseBytes,
    required Uint8List maskPng,
    required RenovStyle style,
    RenovStructure? structure,
    String intensity = 'medium',
    String userHint = '',
  }) async {
    final s = await _settings.load();
    final apiBase = (s['vision_api_base'] as String?)?.trim() ?? '';
    final key = (s['vision_api_key'] as String?)?.trim() ?? '';
    final understandModel = (s['vision_api_model'] as String?)?.trim();
    final genModel = (s['vision_gen_model'] as String?)?.trim();

    final jpeg = RenovApiClient.downscaleJpeg(baseBytes, maxSide: 1280);
    final maskForUse = _resizeMask(maskPng, jpeg) ?? maskPng;

    if (apiBase.isEmpty || key.isEmpty) {
      return RenovResult(
        imageBytes: RenovMask.localTintInMask(
          baseBytes: jpeg,
          maskPng: maskForUse,
          swatchArgb: style.swatch,
        ),
        source: 'local_preview',
        notes: const [
          '未配置视觉 API：局部区仅本地色调示意，不是 AI 局部替换',
        ],
        warnings: const ['请配置 API 后重试以获得云端局部重绘'],
        structure: structure,
        path: 'local-replace',
      );
    }

    final client = RenovApiClient(
      baseUrl: apiBase,
      apiKey: key,
      understandModel:
          (understandModel == null || understandModel.isEmpty)
              ? 'gpt-4o'
              : understandModel,
      generateModel: (genModel == null || genModel.isEmpty) ? null : genModel,
    );

    try {
      final raw = await client.inpaintRegion(
        baseJpeg: jpeg,
        maskPng: maskForUse,
        style: style,
        structure: structure,
        intensity: intensity,
        userHint: userHint,
      );
      return RenovResult(
        imageBytes: RenovMask.composite(
          baseBytes: jpeg,
          editedBytes: raw.imageBytes,
          maskPng: maskForUse,
        ),
        source: raw.source,
        notes: raw.notes,
        warnings: raw.warnings,
        structure: raw.structure ?? structure,
        path: 'local-replace',
      );
    } catch (e) {
      return RenovResult(
        imageBytes: RenovMask.localTintInMask(
          baseBytes: jpeg,
          maskPng: maskForUse,
          swatchArgb: style.swatch,
        ),
        source: 'local_preview',
        notes: const ['云端局部替换失败，已回落 mask 内本地色调示意'],
        warnings: ['局部替换失败：$e'],
        structure: structure,
        path: 'local-replace',
      );
    }
  }

  static int fingerprintJpeg(Uint8List bytes) {
    var h = bytes.length;
    final step = math.max(1, bytes.length ~/ 64);
    for (var i = 0; i < bytes.length; i += step) {
      h = 0x1fffffff & (h * 31 + bytes[i]);
    }
    if (bytes.isNotEmpty) {
      h = 0x1fffffff & (h * 31 + bytes.last);
    }
    return h;
  }

  static RenovStructure? _readUnderstandCache(int fp) {
    final c = _understandCache;
    if (c == null || c.fingerprint != fp) return null;
    // 会话级：离开流程页 endFlowSession 才清；同图换风格一直命中
    return c.structure;
  }

  static void _writeUnderstandCache(int fp, RenovStructure structure) {
    _understandCache = _UnderstandCacheEntry(
      fingerprint: fp,
      structure: structure,
      at: DateTime.now(),
    );
  }

  static void _bumpGenerateCount(int fp) {
    _generateCounts[fp] = (_generateCounts[fp] ?? 0) + 1;
  }

  static Uint8List? _resizeMask(Uint8List maskPng, Uint8List jpeg) {
    final base = img.decodeImage(jpeg);
    final mask = img.decodeImage(maskPng);
    if (base == null || mask == null) return null;
    if (mask.width == base.width && mask.height == base.height) {
      return maskPng;
    }
    final resized =
        img.copyResize(mask, width: base.width, height: base.height);
    return Uint8List.fromList(img.encodePng(resized));
  }

  Future<RenovResult> _local(
    File imageFile,
    RenovStyle style,
    List<List<List<double>>> userAnchors,
    List<List<List<double>>> auto, {
    RenovStructure? structure,
    required String note,
    List<String> extraWarnings = const [],
  }) async {
    final local = await _localPreview(imageFile, style);
    return RenovResult(
      imageBytes: local,
      source: 'local_preview',
      notes: [note],
      warnings: [
        ...extraWarnings,
        ...RenovApiClient.warnLines(userAnchors, auto),
      ],
      structure: structure,
      path: 'local',
    );
  }

  Future<String> saveResultPng(Uint8List bytes, {String? name}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/renov');
    await folder.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${folder.path}/${name ?? 'renov_$stamp'}.png';
    final decoded = img.decodeImage(bytes);
    final out = decoded == null
        ? bytes
        : Uint8List.fromList(img.encodePng(decoded));
    await File(path).writeAsBytes(out, flush: true);
    return path;
  }

  Future<Uint8List> _localPreview(File imageFile, RenovStyle style) async {
    final raw = await imageFile.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      return Uint8List.fromList(raw);
    }
    final r = (style.swatch >> 16) & 0xFF;
    final g = (style.swatch >> 8) & 0xFF;
    final b = style.swatch & 0xFF;
    for (final p in decoded) {
      p
        ..r = (p.r * 0.72 + r * 0.28).round().clamp(0, 255)
        ..g = (p.g * 0.72 + g * 0.28).round().clamp(0, 255)
        ..b = (p.b * 0.72 + b * 0.28).round().clamp(0, 255);
    }
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
  }
}

class _UnderstandCacheEntry {
  _UnderstandCacheEntry({
    required this.fingerprint,
    required this.structure,
    required this.at,
  });

  final int fingerprint;
  final RenovStructure structure;
  final DateTime at;
}
