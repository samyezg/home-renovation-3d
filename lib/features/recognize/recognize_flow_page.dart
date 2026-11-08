import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/floorplan_recognize/floorplan_converter.dart';
import '../../services/floorplan_recognize/floorplan_models.dart';
import '../../services/floorplan_recognize/floorplan_recognize_service.dart';
import '../../services/floorplan_recognize/vision_api_client.dart';
import '../../services/plan_city_settings.dart';
import '../../theme/app_colors.dart';
import '../../utils/image_orientation.dart';
import '../../widgets/floorplan_roi_editor.dart';
import '../../widgets/quick_plan_basics_sheet.dart';
import '../../widgets/scale_edge_preview.dart';

/// I21 P0 + 期次 V/AA/Z：选图 →（可选框选）→ 识别+ROI精校 → 比例尺 → 导入
class RecognizeFlowPage extends StatefulWidget {
  const RecognizeFlowPage({super.key});

  @override
  State<RecognizeFlowPage> createState() => _RecognizeFlowPageState();
}

class _RecognizeFlowPageState extends State<RecognizeFlowPage> {
  final _picker = ImagePicker();
  final _svc = FloorplanRecognizeService();
  final _scrollCtrl = ScrollController();
  final _lengthFocus = FocusNode();

  /// 0 选图 · 1 框选 ROI · 2 识别中 · 3 比例尺
  int _step = 0;
  File? _image;
  double _imageAspect = 4 / 3;
  FloorplanAiResult? _result;
  List<ScaleEdgeOption> _edges = [];
  ScaleEdgeOption? _edge;
  final _lengthCtrl = TextEditingController(text: '360');
  String? _error;
  var _busy = false;

  /// true = 画几笔再识别；false = 自动识别
  var _wantRoi = false;
  List<List<double>>? _roiNorm;

  @override
  void initState() {
    super.initState();
    _lengthFocus.addListener(_onLengthFocus);
  }

  void _onLengthFocus() {
    if (!_lengthFocus.hasFocus) return;
    // 滚到底，避免键盘挡住输入区；确认钮已钉在底栏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _lengthFocus.removeListener(_onLengthFocus);
    _lengthFocus.dispose();
    _scrollCtrl.dispose();
    _lengthCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source, {required bool withRoi}) async {
    setState(() {
      _error = null;
      _busy = true;
      _wantRoi = withRoi;
      _roiNorm = null;
    });
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        imageQuality: 85,
      );
      if (x == null) {
        setState(() => _busy = false);
        return;
      }
      // EXIF bake：显示与裁剪/精校同一坐标系
      final normalized = await ImageOrientation.normalizeToFile(File(x.path));
      final size = await peekImageSize(normalized);
      setState(() {
        _image = normalized;
        _imageAspect =
            size.$2 <= 0 ? 4 / 3 : size.$1 / size.$2;
        _busy = false;
        if (withRoi) {
          _step = 1;
        } else {
          _step = 2;
        }
      });
      if (!withRoi) {
        await _runRecognize();
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '选图失败：$e';
      });
    }
  }

  Future<void> _runRecognize() async {
    final img = _image;
    if (img == null) return;
    if (_wantRoi && (_roiNorm == null || _roiNorm!.length < 3)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先框选或描出外轮廓，再开始识别')),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _step = 2;
    });
    try {
      final raw = await _svc.recognize(
        img,
        roiNorm: _wantRoi ? _roiNorm : null,
      );
      final r = FloorplanConverter.withCleanedRooms(raw);
      final edges = FloorplanConverter.scaleEdgeOptions(r);
      if (!mounted) return;
      setState(() {
        _result = r;
        _edges = edges;
        _edge = edges.isEmpty ? null : edges.first;
        _step = 3;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '识别失败：$e';
        _step = _wantRoi ? 1 : 0;
      });
    }
  }

  Future<void> _importPlan() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final r = _result;
    final edge = _edge;
    if (r == null || edge == null) return;
    final real = double.tryParse(_lengthCtrl.text.trim()) ?? 0;
    if (real < 80 || real > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入合理边长（80～2000 cm）')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (edge.normLength < FloorplanConverter.minPreferredEdgeNorm) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('参照边偏短'),
            content: Text(
              '当前边约占图面 ${(edge.normLength * 100).round()}%，'
              '若按 ${real.round()} cm 换算，整套可能偏大。'
              '建议改选图上更长的「客厅开间」。仍要继续吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('去改选'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍导入'),
              ),
            ],
          ),
        );
        if (go != true) {
          setState(() => _busy = false);
          return;
        }
      }
      final scale = ScaleInfo(
        edgeNormLength: edge.normLength,
        realLengthCm: real,
      );
      final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
      var plan = await createPlanWithSettings(name: '拍照识别-$stamp');
      plan = FloorplanConverter.toPlan(
        r,
        scale,
        name: plan.meta.name,
        building: plan.building,
      );
      // bad case：warning 随方案导出
      plan.annotations.recognizeWarnings = List<String>.from(r.warnings);
      plan.annotations.recognizeSource = r.source;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final dest = File(
          '${dir.path}/plans/${plan.meta.id}/source.jpg',
        );
        await dest.parent.create(recursive: true);
        if (_image != null) await _image!.copy(dest.path);
        plan.annotations.screenshotPaths = [
          ...plan.annotations.screenshotPaths,
          dest.path,
        ];
      } catch (_) {}
      if (!mounted) return;
      final ok = await showQuickPlanBasicsSheet(context, plan);
      if (!mounted || ok != true) {
        setState(() => _busy = false);
        return;
      }
      await applyCityFromSettings(plan);
      if (!mounted) return;
      Navigator.of(context).pop(plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  void _resetPick() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = 0;
      _result = null;
      _image = null;
      _roiNorm = null;
      _wantRoi = false;
      _edges = [];
      _edge = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('拍照识别户型'),
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _stepHeader(),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (_step == 0) _pickSection(),
                  if (_step == 1) _roiSection(),
                  if (_step == 2) _recognizingSection(),
                  if (_step >= 3) ...[
                    if (_image != null && _step == 3 && _edges.isNotEmpty)
                      ScaleEdgePreview(
                        image: FileImage(_image!),
                        imageAspectRatio: _imageAspect,
                        edges: _edges,
                        selected: _edge,
                        onSelect: (e) => setState(() => _edge = e),
                      )
                    else if (_image != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Image.file(_image!, fit: BoxFit.contain),
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (_result != null) ..._resultSummary(_result!),
                    if (_step == 3) ..._scaleFields(),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  // 给键盘留一点滚动余量
                  SizedBox(height: _step == 3 ? 24 : 0),
                ],
              ),
            ),
          ),
          if (_step == 3) _scaleBottomBar(),
        ],
      ),
    );
  }

  Widget _stepHeader() {
    final labels = ['选图', '框选', '识别', '比例尺'];
    int visualStep(int i) {
      if (!_wantRoi && i == 1) {
        return _step >= 2 ? 1 : -1;
      }
      return i;
    }

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: _step > visualStep(i - 1) && visualStep(i - 1) >= 0
                    ? AppColors.brand
                    : AppColors.border,
              ),
            ),
          CircleAvatar(
            radius: 14,
            backgroundColor: (!_wantRoi && i == 1)
                ? AppColors.border
                : (_step >= i ? AppColors.brand : AppColors.border),
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
          '拍一张或上传户型图纸，自动生成可编辑方案。复杂图纸可先「画几笔再识别」框住外轮廓。'
          '无网络或未配置识图接口时，使用本地几何示意（可继续手改）。',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 16),
        const Text(
          '自动识别',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _pick(ImageSource.camera, withRoi: false),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('拍照 · 自动识别'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _pick(ImageSource.gallery, withRoi: false),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('相册 · 自动识别'),
        ),
        const SizedBox(height: 20),
        const Text(
          '画几笔再识别',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '先框选或描外轮廓，只识别框内；随后仍会做 ROI 精校。',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy
              ? null
              : () => _pick(ImageSource.camera, withRoi: true),
          icon: const Icon(Icons.crop_free),
          label: const Text('拍照 · 画几笔再识别'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _pick(ImageSource.gallery, withRoi: true),
          icon: const Icon(Icons.crop),
          label: const Text('相册 · 画几笔再识别'),
        ),
        const SizedBox(height: 16),
        Text(
          '提示：清晰、正对、少反光的开发商户型图效果更好。可在「我的」配置视觉 API 以启用云端识别。',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _roiSection() {
    final img = _image;
    if (img == null) {
      return const Text('未选图');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '框选外轮廓',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          '框住整套户型即可；框外标题栏、图例会被忽略。也可切换「描外轮廓」。',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        FloorplanRoiEditor(
          image: FileImage(img),
          imageAspectRatio: _imageAspect,
          initialPolygon: _roiNorm,
          onChanged: (poly) => setState(() => _roiNorm = poly),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _roiNorm == null || _roiNorm!.length < 3
              ? null
              : _runRecognize,
          child: const Text('开始识别'),
        ),
        TextButton(
          onPressed: _busy ? null : _resetPick,
          child: const Text('重新选图'),
        ),
      ],
    );
  }

  Widget _recognizingSection() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Text(
          _wantRoi && _roiNorm != null
              ? '正在识别框内户型结构…'
              : '正在识别户型结构…',
        ),
        const SizedBox(height: 8),
        const Text(
          '方案 D：云端语义（若已配置）→ ROI 精校 → 本地几何兜底',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _resultSummary(FloorplanAiResult r) {
    return [
      Text(
        '识别来源：${r.source == 'vision_api' ? '云端视觉' : '本地几何示意'} · '
        '房间 ${r.rooms.length} · 门 ${r.doors.length} · 窗 ${r.windows.length}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final room in r.rooms)
            Chip(
              label: Text(room.name),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      for (final w in r.warnings)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '· $w',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      const SizedBox(height: 12),
    ];
  }

  /// 比例尺表单（确认钮在底栏，避免键盘遮挡）
  List<Widget> _scaleFields() {
    final edgeInList = _edge != null && _edges.any((e) => e.id == _edge!.id);
    return [
      const Text(
        '设置比例尺',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      const Text(
        '看图上橙色双向箭头：填入这段墙的实际长度（cm）。'
        '住宅常用客厅开间，例如 360（即 3.6 米）。',
        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<ScaleEdgeOption>(
        key: ValueKey(_edge?.id ?? 'none'),
        initialValue: edgeInList ? _edge : null,
        isExpanded: true,
        items: [
          for (final e in _edges)
            DropdownMenuItem(
              value: e,
              child: Text(
                e.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _edge = v);
        },
        decoration: const InputDecoration(
          labelText: '参照边（与图示联动）',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _lengthCtrl,
        focusNode: _lengthFocus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: const InputDecoration(
          labelText: '实际长度 (cm)',
          hintText: '客厅开间示例：360',
          helperText: '1 米 = 100 cm；3.6 米请填 360 · 完成后点下方「确认」',
          border: OutlineInputBorder(),
        ),
      ),
      TextButton(
        onPressed: _busy ? null : _resetPick,
        child: const Text('重新选图'),
      ),
    ];
  }

  Widget _scaleBottomBar() {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      elevation: 8,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + (bottom > 0 ? 0 : 0)),
        child: SafeArea(
          top: false,
          child: FilledButton(
            onPressed: _busy || _edge == null ? null : _importPlan,
            child: const Text('确认比例尺并导入画布'),
          ),
        ),
      ),
    );
  }
}
