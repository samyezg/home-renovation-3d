import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/diy_catalog.dart';
import '../../models/domain.dart';
import '../../models/plan.dart';
import '../../services/diagnosis_engine.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../acceptance/acceptance_page.dart';
import '../diy/diy_steps_page.dart';
import '../safety/safety_page.dart';
import '../viewer3d/viewer3d_page.dart';

class DiagnosisReportPage extends StatefulWidget {
  const DiagnosisReportPage({super.key, required this.plan});

  final PlanDocument plan;

  @override
  State<DiagnosisReportPage> createState() => _DiagnosisReportPageState();
}

class _DiagnosisReportPageState extends State<DiagnosisReportPage> {
  DiagnosisReport? report;
  var offsetEnabled = true;
  final _shotKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final s = await SettingsRepository().load();
    offsetEnabled = s['city_offset_enabled'] as bool? ?? true;
    final r = DiagnosisEngine(cityOffsetEnabled: offsetEnabled).run(widget.plan);
    if (mounted) setState(() => report = r);
  }

  Future<void> _shareLongImage() async {
    try {
      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/qingzhuangjia_report_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '轻装家诊断报告（仅供参考）',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$e')),
        );
      }
    }
  }

  Future<void> _shareFile(String path, {String text = '轻装家 3D 截图'}) async {
    try {
      final f = File(path);
      if (!await f.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在，可能已被清理')),
          );
        }
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: text),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败：$e')),
        );
      }
    }
  }

  void _openShotViewer(List<String> shots, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ShotViewerPage(
          paths: shots,
          initialIndex: index,
          onShare: (path) => _shareFile(path),
        ),
      ),
    );
  }

  Widget _shotGallery(List<String> shots) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('沟通用图', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          '3D 截图 ${shots.length} 张 · 点图浏览，可单独分享给设计师',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: shots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final path = shots[i];
              final file = File(path);
              return InkWell(
                onTap: () => _openShotViewer(shots, i),
                borderRadius: BorderRadius.circular(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: file.existsSync()
                        ? Image.file(file, fit: BoxFit.cover)
                        : Container(
                            color: AppColors.border,
                            alignment: Alignment.center,
                            child: const Text('缺失', style: TextStyle(fontSize: 12)),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _shareFile(shots.first, text: '轻装家 3D 截图（沟通用）'),
          icon: const Icon(Icons.ios_share_outlined, size: 18),
          label: const Text('分享最近一张 3D 截图'),
        ),
      ],
    );
  }

  List<String> _highlightBullets(DiagnosisReport report) {
    if (report.highlights.isNotEmpty) {
      return report.highlights.take(5).toList();
    }
    final fromAdvices = report.advices
        .map((a) => a.title.trim())
        .where((t) => t.isNotEmpty)
        .take(5)
        .toList();
    if (fromAdvices.isNotEmpty) return fromAdvices;
    return [report.summaryTitle];
  }

  Future<void> _generateChecklist() async {
    final report = this.report;
    if (report == null) return;
    final repo = ChecklistRepository();
    var added = 0;
    for (final a in report.advices) {
      if (a.diyLevel == 'L3') continue;
      final tid = a.templateId;
      if (tid == null) continue;
      final t = DiyCatalog.byId(tid);
      if (t == null) continue;
      await repo.add(
        ChecklistLine(
          id: 'cl_${const Uuid().v4().substring(0, 8)}',
          category: t.listCategory,
          title: t.title,
          specHint: t.listSpecHint,
          source: a.ruleId,
          depthCm: a.cabinetDepthCm,
          skuId: a.cabinetDepthCm == null ? null : 'cab_${a.cabinetDepthCm}',
          price: null,
        ),
      );
      added++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added > 0
              ? '已写入改造清单，可到底部清单页查看'
              : '暂无可写入的改造项，可先完善建议后再试',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final b = plan.building;
    final report = this.report;
    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('诊断报告')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final shots = plan.annotations.screenshotPaths;
    final bullets = _highlightBullets(report);

    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断报告'),
        actions: [
          IconButton(
            tooltip: '长图分享',
            onPressed: _shareLongImage,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          RepaintBoundary(
            key: _shotKey,
            child: ColoredBox(
              color: AppColors.bg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        '${plan.meta.name} · ${b.areaBuildM2.toStringAsFixed(0)}㎡ · ${b.cityName}\n'
                        '本地草稿 · 不上云',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    color: AppColors.brandSoft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '重点摘要',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            report.summaryTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final line in bullets)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '· $line',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          const Text(
                            AppConstants.disclaimer,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      '详细分析',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    children: [
                      SizedBox(
                        height: 108,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final m in report.metrics)
                              _MetricChip(
                                title: m.title,
                                value: m.value,
                                sub: m.sub,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        report.summaryBody,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '建议排序说明（共 ${report.allAdviceCount} 条，展示前 ${report.advices.length}）',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final line in report.rankExplain)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              line,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.35,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('优先建议', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (report.advices.isEmpty)
                    const Text('暂无优先建议，可完善户型与收纳标记后再诊。')
                  else
                    ...report.advices.map(_adviceCard),
                ],
              ),
            ),
          ),
          if (shots.isNotEmpty) ...[
            const SizedBox(height: 12),
            _shotGallery(shots),
          ],
          const SizedBox(height: 16),
          const Text('下一步', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _nextAction(
            title: '查看 3D 预览',
            subtitle: '在三维空间中查看你的户型，可截图回写到本页',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => Viewer3dPage(plan: plan)),
              );
              if (mounted) setState(() {});
            },
          ),
          _nextAction(
            title: '调整户型',
            subtitle: '返回修改房间与门窗',
            onTap: () => Navigator.of(context).pop(),
          ),
          _nextAction(
            title: '生成改造清单',
            subtitle: '把建议加入可勾选清单',
            onTap: _generateChecklist,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _shareLongImage,
            child: const Text('长图分享报告'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final text = await ChecklistRepository().exportText();
              if (!context.mounted) return;
              await showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('改造清单文本'),
                  content: SingleChildScrollView(child: Text(text)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('查看/导出清单文本'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AcceptancePage()),
              );
            },
            child: const Text('去验收自查（25 条）'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SafetyPage(familyStage: plan.building.familyStage),
                ),
              );
            },
            child: const Text('安全自查（可选）'),
          ),
        ],
      ),
    );
  }

  Widget _nextAction({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
        onTap: onTap,
      ),
    );
  }

  Widget _adviceCard(DiagAdvice a) {
    final isL3 = a.diyLevel == 'L3';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isL3 ? const Color(0x1AB54A3F) : AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${a.diyLevel}·${a.stackLabel}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isL3 ? AppColors.danger : AppColors.brand,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              a.rankReason,
              style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
            ),
            const SizedBox(height: 8),
            Text(a.reason, style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (!isL3 && a.templateId != null)
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DiyStepsPage(
                            templateId: a.templateId!,
                            adviceTitle: a.title,
                          ),
                        ),
                      );
                    },
                    child: const Text('看步骤'),
                  ),
                if (!isL3 && a.cabinetDepthCm != null)
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Viewer3dPage(
                            plan: widget.plan,
                            spawnSku: 'cab_${a.cabinetDepthCm}',
                          ),
                        ),
                      );
                    },
                    child: const Text('放入3D'),
                  ),
                if (!isL3 && a.templateId != null)
                  OutlinedButton(
                    onPressed: () async {
                      final t = DiyCatalog.byId(a.templateId!);
                      if (t == null) return;
                      await ChecklistRepository().add(
                        ChecklistLine(
                          id: 'cl_${const Uuid().v4().substring(0, 8)}',
                          category: t.listCategory,
                          title: t.title,
                          specHint: t.listSpecHint,
                          source: a.ruleId,
                          depthCm: a.cabinetDepthCm,
                          skuId: a.cabinetDepthCm == null
                              ? null
                              : 'cab_${a.cabinetDepthCm}',
                          price: null,
                        ),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已加入改造清单')),
                        );
                      }
                    },
                    child: const Text('加入清单'),
                  ),
                if (isL3)
                  OutlinedButton(
                    onPressed: () {
                      final tid = a.templateId ?? 'T-L3-DOOR-01';
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DiyStepsPage(templateId: tid, adviceTitle: a.title),
                        ),
                      );
                    },
                    child: const Text('了解为何'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.title, required this.value, required this.sub});

  final String title;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppColors.textDisabled, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// 期次 T：3D 截图全屏浏览 + 单张分享
class _ShotViewerPage extends StatefulWidget {
  const _ShotViewerPage({
    required this.paths,
    required this.initialIndex,
    required this.onShare,
  });

  final List<String> paths;
  final int initialIndex;
  final void Function(String path) onShare;

  @override
  State<_ShotViewerPage> createState() => _ShotViewerPageState();
}

class _ShotViewerPageState extends State<_ShotViewerPage> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.paths.length - 1);
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.paths.length}'),
        actions: [
          IconButton(
            tooltip: '分享此图',
            onPressed: () => widget.onShare(widget.paths[_index]),
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.paths.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (ctx, i) {
          final f = File(widget.paths[i]);
          if (!f.existsSync()) {
            return const Center(
              child: Text('图片文件不存在', style: TextStyle(color: Colors.white70)),
            );
          }
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 8,
            child: Center(child: Image.file(f, fit: BoxFit.contain)),
          );
        },
      ),
    );
  }
}
