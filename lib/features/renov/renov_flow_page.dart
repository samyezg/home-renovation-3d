import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/renov_styles.dart';
import '../../services/renov/renov_api_client.dart';
import '../../services/renov/renov_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/before_after_slider.dart';
import '../../widgets/structure_anchor_editor.dart';
import 'local_adjust_page.dart';

/// I21 P1：拍照 →（可选）结构描线 → 选风格 → 生成效果图 → 前后对比
class RenovFlowPage extends StatefulWidget {
  const RenovFlowPage({super.key});

  @override
  State<RenovFlowPage> createState() => _RenovFlowPageState();
}

class _RenovFlowPageState extends State<RenovFlowPage> {
  final _picker = ImagePicker();
  final _svc = RenovService();

  /// 0 选图 · 1 描线锚点 · 2 风格 · 3 生成中 · 4 结果
  int _step = 0;
  File? _image;
  List<List<List<double>>> _anchors = [];
  var _useAutoEdge = true;
  RenovStyle _style = RenovStyles.all.first;
  String _intensity = 'medium';
  RenovResult? _result;
  String? _savedPath;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    RenovService.endFlowSession();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1536,
        imageQuality: 85,
      );
      if (x == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _image = File(x.path);
        _anchors = [];
        _result = null;
        _savedPath = null;
        _step = 1;
        _busy = false;
      });
      // 新图：不沿用上一张的生成次数；理解缓存按指纹自然隔离
      try {
        final bytes = await File(x.path).readAsBytes();
        final jpeg = RenovApiClient.downscaleJpeg(bytes, maxSide: 1280);
        RenovService.resetSessionForFingerprint(
          RenovService.fingerprintJpeg(jpeg),
        );
      } catch (_) {}
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '选图失败：$e';
      });
    }
  }

  Future<void> _runGenerate({bool acknowledgeSoftLimit = false}) async {
    final img = _image;
    if (img == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _step = 3;
    });
    try {
      final r = await _svc.generate(
        imageFile: img,
        style: _style,
        userAnchors: _anchors,
        useAutoEdge: _useAutoEdge,
        intensity: _intensity,
        acknowledgeSoftLimit: acknowledgeSoftLimit,
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _step = 4;
        _busy = false;
      });
    } on RenovSoftLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 2;
      });
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已达生成软上限'),
          content: Text(
            '$e\n\n是否仍要继续生成下一次？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('再生成一次'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await _runGenerate(acknowledgeSoftLimit: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '生成失败：$e';
        _step = 2;
      });
    }
  }

  Future<void> _share() async {
    final r = _result;
    if (r == null) return;
    try {
      final path = _savedPath ?? await _svc.saveResultPng(r.imageBytes);
      _savedPath = path;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: '轻装家 · ${_style.name}改造预览',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$e')),
      );
    }
  }

  Future<void> _saveLocal() async {
    final r = _result;
    if (r == null) return;
    try {
      final path = await _svc.saveResultPng(r.imageBytes);
      setState(() => _savedPath = path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到本机：$path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<void> _openLocalReplace() async {
    final r = _result;
    if (r == null) return;
    final updated = await Navigator.of(context).push<RenovResult>(
      MaterialPageRoute(
        builder: (_) => LocalAdjustPage(
          baseBytes: r.imageBytes,
          style: _style,
          structure: r.structure,
          intensity: _intensity,
        ),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _result = updated;
      _savedPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照改造')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _stepHeader(),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          if (_step == 0) _pickSection(),
          if (_step == 1) _anchorSection(),
          if (_step == 2) _styleSection(),
          if (_step == 3) _loadingSection(),
          if (_step == 4) _resultSection(),
          if (_busy && _step != 3) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _stepHeader() {
    const labels = ['选图', '描线', '风格', '效果'];
    final visual = switch (_step) {
      0 => 0,
      1 => 1,
      2 => 2,
      3 || 4 => 3,
      _ => 0,
    };
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: visual > i - 1 ? AppColors.brand : AppColors.border,
              ),
            ),
          CircleAvatar(
            radius: 14,
            backgroundColor:
                visual >= i ? AppColors.brand : AppColors.border,
            foregroundColor: Colors.white,
            child: Text(
              '${i + 1}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pickSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '拍一张房间实景：先做结构理解（写入提示词），再按风格做弱约束改造（路径 B）。'
          '墙线/门窗对齐不保证。可选描墙线加强提示。图片将上传云端 AI（需在「我的」配置 API）。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _pick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('拍照'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('从相册选择'),
        ),
        const SizedBox(height: 12),
        Text(
          '未配置 API 时仅做本地色调示意，不是 AI 改造图；真实效果以云端生成为准。',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _anchorSection() {
    final img = _image;
    if (img == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '结构锚点（可选）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          '优先级：用户描线 > 自动边缘 > 无锚点。描线写入提示词（弱约束），非强制结构条件。可跳过。',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        StructureAnchorEditor(
          image: FileImage(img),
          initialStrokes: _anchors.isEmpty ? null : _anchors,
          onChanged: (s) => setState(() => _anchors = s),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('未描线时使用自动边缘（弱约束）'),
          value: _useAutoEdge,
          onChanged: (v) => setState(() => _useAutoEdge = v),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : () => setState(() => _step = 2),
          child: Text(
            _anchors.isEmpty ? '跳过描线，选风格' : '下一步：选风格',
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = 0;
                    _image = null;
                    _anchors = [];
                  }),
          child: const Text('重新选图'),
        ),
      ],
    );
  }

  Widget _styleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(_image!, fit: BoxFit.contain),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          '选择风格',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in RenovStyles.all)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: Color(s.swatch),
                  radius: 8,
                ),
                label: Text(s.name),
                selected: _style.id == s.id,
                onSelected: (_) => setState(() => _style = s),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _style.blurb,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        const Text(
          '改造强度',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'light', label: Text('轻度')),
            ButtonSegment(value: 'medium', label: Text('中度')),
            ButtonSegment(value: 'heavy', label: Text('重度')),
          ],
          selected: {_intensity},
          onSelectionChanged: (v) => setState(() => _intensity = v.first),
        ),
        const SizedBox(height: 8),
        Text(
          '同一张图：结构理解在本流程内缓存（离开本页清除）；'
          '云端整图生成按图累计软上限 ${RenovService.softGenerateLimit} 次'
          '（确认只放行下一次，非按天）。',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : () => _runGenerate(),
          child: const Text('生成效果图'),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 1),
          child: const Text('返回描线'),
        ),
      ],
    );
  }

  Widget _loadingSection() {
    return const Column(
      children: [
        SizedBox(height: 48),
        Text('正在理解空间并生成改造图…'),
        SizedBox(height: 8),
        Text(
          '路径 B：结构写入提示词后做弱约束风格迁移；失败会降级到弱路径或本地色调',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 24),
        CircularProgressIndicator(),
      ],
    );
  }

  Widget _resultSection() {
    final r = _result;
    final img = _image;
    if (r == null || img == null) return const SizedBox.shrink();
    final isA2 = r.path == 'A2' || r.source == 'images_api_fallback';
    final pathLabel = switch (r.path) {
      'B' => '路径 B · 风格迁移（弱约束）',
      'B-lite' => '路径 B 简化 · 弱约束带图',
      'A1' => '路径 A1 · 仍基于您的照片',
      'A2' => '路径 A2 · AI 参考图（非实景）',
      'A' => '路径 A · 弱路径降级',
      'local-replace' => '局部替换 · 涂抹重绘（弱约束）',
      _ => '本地色调示意（非 AI 改造图）',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isA2) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '当前无法基于您的照片改造，以下为 AI 参考效果图，非您家实景。'
                '左侧对照仅供参考，请勿当作自家改造结果。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF9F1239),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        BeforeAfterSlider(
          before: FileImage(img),
          after: MemoryImage(r.imageBytes),
        ),
        const SizedBox(height: 12),
        Text(
          '$pathLabel · ${_style.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (r.structure != null && !r.structure!.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              r.structure!.humanFriendlySummary(),
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text(
                '查看识别明细',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                '中心点坐标（非轮廓）· 供核对',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    [
                      '说明：结构信息为中心点级，无 polygon / w·h / 朝向。',
                      ...r.structure!.detailLines(),
                      '',
                      r.structure!.toPrettyJson(),
                    ].join('\n'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (r.structure == null || r.structure!.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '· 暂无空间要素识别结果',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        for (final n in r.notes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '· $n',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        for (final w in r.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '· $w',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isA2 && w.contains('非您家实景')
                    ? const Color(0xFF9F1239)
                    : AppColors.textSecondary,
                fontWeight: isA2 && w.contains('非您家实景')
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _share,
          icon: const Icon(Icons.share_outlined),
          label: const Text('分享效果图'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saveLocal,
          icon: const Icon(Icons.save_alt),
          label: const Text('保存到本机'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openLocalReplace,
          icon: const Icon(Icons.brush_outlined),
          label: const Text('局部替换'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = 2;
            _result = null;
          }),
          child: const Text('换个风格'),
        ),
        TextButton(
          onPressed: () {
            RenovService.endFlowSession();
            setState(() {
              _step = 0;
              _image = null;
              _anchors = [];
              _result = null;
              _savedPath = null;
            });
          },
          child: const Text('重新开始'),
        ),
      ],
    );
  }
}
