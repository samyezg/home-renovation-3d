import 'package:flutter/material.dart';

import '../../data/demo_plans.dart';
import '../../models/plan.dart';
import '../../services/repositories.dart';
import '../../services/plan_city_settings.dart';
import '../../theme/app_colors.dart';
import '../../widgets/plan_template_sheet.dart';
import '../../widgets/plan_thumb.dart';
import '../../widgets/quick_plan_basics_sheet.dart';
import '../checklist/checklist_page.dart';
import '../plan/plan_page.dart';
import '../recognize/recognize_flow_page.dart';
import '../renov/renov_flow_page.dart';
import '../viewer3d/viewer3d_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _repo = PlanRepository();
  List<PlanDocument> _recent = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final list = await _repo.listPlans();
    if (!mounted) return;
    setState(() {
      _recent = list.take(8).toList();
      _loading = false;
    });
  }

  Future<void> _startDesign() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final pick = await showPlanTemplateSheet(context);
    if (!mounted || pick == null) return;
    if (pick is PhotoRecognizeChoice) {
      final plan = await Navigator.of(context).push<PlanDocument>(
        MaterialPageRoute(builder: (_) => const RecognizeFlowPage()),
      );
      if (!mounted || plan == null) return;
      await _repo.save(plan);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlanWorkspacePage(plan: plan, initialTab: 1),
        ),
      );
      await _loadRecent();
      return;
    }
    late PlanDocument plan;
    if (pick is BlankPlanChoice) {
      plan = await createPlanWithSettings();
    } else if (pick is PlanDocument) {
      plan = pick;
      await applyCityFromSettings(plan);
    } else {
      return;
    }
    if (!mounted) return;
    final ok = await showQuickPlanBasicsSheet(context, plan);
    if (!mounted || ok != true) return;
    await _repo.save(plan);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanWorkspacePage(plan: plan, initialTab: 1),
      ),
    );
    await _loadRecent();
  }

  Future<void> _followDemo() async {
    final plan = DemoPlans.twoBed();
    await applyCityFromSettings(plan);
    await _repo.save(plan);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanWorkspacePage(plan: plan, initialTab: 1),
      ),
    );
    await _loadRecent();
  }

  Future<void> _openPlan(PlanDocument plan) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlanWorkspacePage(plan: plan, initialTab: 1),
      ),
    );
    await _loadRecent();
  }

  /// 首页「看 3D」：单方案直进；多方案先选
  Future<void> _open3dPreview() async {
    final list = await _repo.listPlans();
    if (!mounted) return;
    if (list.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('还没有方案'),
          content: const Text('先画好户型，再来看立体预览。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去画户型'),
            ),
          ],
        ),
      );
      if (go == true && mounted) await _startDesign();
      return;
    }
    setState(() => _recent = list.take(8).toList());
    PlanDocument? plan = list.first;
    if (list.length > 1) {
      plan = await showModalBottomSheet<PlanDocument>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '选择要预览的方案',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '可任选本地方案进入 3D',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * 0.45,
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final p = list[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: PlanThumb(plan: p, width: 56, height: 44),
                          title: Text(p.meta.name),
                          subtitle: Text(
                            '${p.building.areaBuildM2}㎡ · ${p.rooms.length} 空间'
                            '${i == 0 ? ' · 最近' : ''}',
                          ),
                          trailing: const Icon(Icons.view_in_ar_outlined),
                          onTap: () => Navigator.pop(ctx, p),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (plan == null || !mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Viewer3dPage(plan: plan!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('轻装家')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text('户型诊断与软装DIY', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          const Text(
            '开始设计',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '手绘户型 → 诊断建议 → 3D 预览 → 改造清单',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _startDesign,
            child: const Text('立即开始'),
          ),
          const SizedBox(height: 14),
          Material(
            color: AppColors.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RenovFlowPage()),
                );
              },
              child: const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Icon(Icons.camera_enhance_outlined, color: AppColors.brand),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '拍照改造',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '拍房间实景，看改造效果（可描墙线防变形）',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _WorkbenchCard(
                icon: Icons.edit_outlined,
                title: '画户型',
                subtitle: '标房间门窗',
                onTap: _startDesign,
              ),
              _WorkbenchCard(
                icon: Icons.analytics_outlined,
                title: '智能诊断',
                subtitle: '选择方案后诊断',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlanPage()),
                  );
                },
              ),
              _WorkbenchCard(
                icon: Icons.view_in_ar_outlined,
                title: '看 3D',
                subtitle: '选择方案预览',
                onTap: _open3dPreview,
              ),
              _WorkbenchCard(
                icon: Icons.checklist_outlined,
                title: '改造清单',
                subtitle: '本地草稿条目',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChecklistPage()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '最近方案',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const SizedBox(
              height: 88,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_recent.isEmpty)
                    _DashedNewPlanCard(onTap: _startDesign)
                  else
                    for (final p in _recent) ...[
                      _RecentPlanCard(
                        plan: p,
                        onTap: () => _openPlan(p),
                      ),
                      const SizedBox(width: 10),
                    ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _followDemo,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('跟着示例走一遍'),
          ),
        ],
      ),
    );
  }
}

class _WorkbenchCard extends StatelessWidget {
  const _WorkbenchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: AppColors.brand),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentPlanCard extends StatelessWidget {
  const _RecentPlanCard({required this.plan, required this.onTap});

  final PlanDocument plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlanThumb(plan: plan, width: 104, height: 40),
                const Spacer(),
                Text(
                  plan.meta.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedNewPlanCard extends StatelessWidget {
  const _DashedNewPlanCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: CustomPaint(
            painter: _DashedBorderPainter(),
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '新建第一个方案',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(10),
    );
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dash = 5.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
