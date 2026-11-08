import 'package:flutter/material.dart';

import '../../data/demo_plans.dart';
import '../../models/plan.dart';
import '../../services/city_tier_catalog.dart';
import '../../services/diagnosis_engine.dart';
import '../../services/plan_city_settings.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../../widgets/plan_template_sheet.dart';
import '../../widgets/plan_thumb.dart';
import '../../widgets/quick_plan_basics_sheet.dart';
import '../diagnosis/diagnosis_report_page.dart';
import '../recognize/recognize_flow_page.dart';
import '../renov/renov_flow_page.dart';
import '../viewer3d/viewer3d_page.dart';
import 'plan_canvas.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  final _repo = PlanRepository();
  final _searchCtrl = TextEditingController();
  late Future<List<PlanDocument>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _repo.listPlans();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _future = _repo.listPlans());

  Future<void> _open(PlanDocument? existing) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final plan = existing ?? await createPlanWithSettings();
    if (!mounted) return;
    await Navigator.of(context).push<PlanDocument>(
      MaterialPageRoute(
        builder: (_) => PlanWorkspacePage(
          plan: plan,
          initialTab: 1,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _loadDemo() async {
    final plan = DemoPlans.twoBed();
    await applyCityFromSettings(plan);
    await _repo.save(plan);
    _reload();
    if (!mounted) return;
    await _open(plan);
  }

  Future<void> _showCreateSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final pick = await showPlanTemplateSheet(context);
    if (!mounted || pick == null) return;
    if (pick is PhotoRecognizeChoice) {
      final plan = await Navigator.of(context).push<PlanDocument>(
        MaterialPageRoute(builder: (_) => const RecognizeFlowPage()),
      );
      if (!mounted || plan == null) return;
      await _repo.save(plan);
      await _open(plan);
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
    await _open(plan);
  }

  List<PlanDocument> _filtered(List<PlanDocument> list) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((p) => p.meta.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('方案'),
        actions: [
          IconButton(
            tooltip: '拍照改造',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RenovFlowPage()),
              );
            },
            icon: const Icon(Icons.camera_enhance_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        icon: const Icon(Icons.add),
        label: const Text('新建方案'),
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '还没有方案',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '第一步：创建你的户型',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _open(null),
                      child: const Text('新建'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _loadDemo,
                      child: const Text('载入示例'),
                    ),
                  ],
                ),
              ),
            );
          }
          final shown = _filtered(list);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索方案名称',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('无匹配方案'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final p = shown[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: PlanThumb(plan: p, width: 50, height: 40),
                              title: Text(p.meta.name),
                              subtitle: Text(
                                '${p.building.areaBuildM2.toStringAsFixed(0)}㎡ · '
                                '${p.rooms.length} 空间 · ${p.meta.updatedAt.split('T').first}',
                              ),
                              trailing: Tooltip(
                                message: '更多',
                                child: PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'del') {
                                      await _repo.delete(p.meta.id);
                                      _reload();
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'del',
                                      child: Text('删除'),
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () => _open(p),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PlanWorkspacePage extends StatefulWidget {
  const PlanWorkspacePage({
    super.key,
    required this.plan,
    this.initialTab = 1,
  });

  final PlanDocument plan;

  /// 0=基础信息 · 1=户型画布（默认画布，避免进页即弹键盘）
  final int initialTab;

  @override
  State<PlanWorkspacePage> createState() => _PlanWorkspacePageState();
}

class _PlanWorkspacePageState extends State<PlanWorkspacePage>
    with SingleTickerProviderStateMixin {
  late PlanDocument plan;
  late TabController _tabs;
  final _repo = PlanRepository();
  var _cityHint = '填写城市名后可自动建议级别（可改）';
  var _catalogReady = false;
  List<String> _citySuggestions = const [];
  final _nameCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _netCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _bathCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _redCtrl = TextEditingController();
  final _blueCtrl = TextEditingController();
  final _storageCtrl = TextEditingController();
  final _openCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    plan = widget.plan;
    final idx = widget.initialTab.clamp(0, 1);
    _tabs = TabController(length: 2, vsync: this, initialIndex: idx);
    _syncControllers();
    _bootstrapCityCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _bootstrapCityCatalog() async {
    await CityTierCatalog.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _catalogReady = true;
      _refreshCityHint();
    });
  }

  void _refreshCityHint() {
    if (!_catalogReady) return;
    final hit = CityTierCatalog.resolve(plan.building.cityName);
    if (plan.building.cityTierIsManual) {
      _cityHint =
          '级别已手改（${CityTierCatalog.tierLabel(plan.building.cityTier)}）；改城市名不会覆盖';
    } else {
      _cityHint = CityTierCatalog.hintFor(hit);
    }
  }

  /// 城市名变更：未手改级别时按榜单建议覆盖；已手改只更新提示。
  void _onCityNameCommitted(String raw) {
    final name = raw.trim().isEmpty ? '成都' : raw.trim();
    final normalized = CityTierCatalog.normalize(name);
    final hit = CityTierCatalog.resolve(normalized);
    setState(() {
      plan.building.cityName =
          hit.matchedName.isEmpty ? name : hit.matchedName;
      _cityCtrl.text = plan.building.cityName;
      if (!plan.building.cityTierIsManual) {
        plan.building.cityTier = hit.tier;
        plan.building.cityTierSource = 'auto';
      }
      _refreshCityHint();
    });
  }

  void _onCityTierManual(String? v) {
    setState(() {
      plan.building.cityTier = v ?? 'tier2';
      plan.building.cityTierSource = 'manual';
      _refreshCityHint();
    });
  }

  void _syncControllers() {
    _nameCtrl.text = plan.meta.name;
    _areaCtrl.text = plan.building.areaBuildM2.toString();
    _netCtrl.text = plan.building.areaNetM2?.toString() ?? '';
    _roomsCtrl.text = '${plan.building.roomCount}';
    _bathCtrl.text = '${plan.building.bathroomCount}';
    _cityCtrl.text = plan.building.cityName;
    _redCtrl.text = plan.annotations.redRulerCm?.toString() ?? '';
    _blueCtrl.text = plan.annotations.blueRulerCm?.toString() ?? '';
    _storageCtrl.text = plan.building.storageRatioSurvey == null
        ? ''
        : ((plan.building.storageRatioSurvey! * 100).toStringAsFixed(0));
    _openCtrl.text = plan.annotations.openConnections.join(',');
    _refreshCityHint();
  }

  void _applyFields() {
    plan.meta.name =
        _nameCtrl.text.trim().isEmpty ? '未命名方案' : _nameCtrl.text.trim();
    plan.building.areaBuildM2 =
        double.tryParse(_areaCtrl.text) ?? plan.building.areaBuildM2;
    plan.building.areaNetM2 = double.tryParse(_netCtrl.text);
    plan.building.roomCount =
        int.tryParse(_roomsCtrl.text) ?? plan.building.roomCount;
    plan.building.bathroomCount =
        int.tryParse(_bathCtrl.text) ?? plan.building.bathroomCount;
    plan.building.cityName =
        _cityCtrl.text.trim().isEmpty ? '成都' : _cityCtrl.text.trim();
    // 保存前若仍为 auto，再对齐一次榜单建议（避免只改字未失焦）
    if (!plan.building.cityTierIsManual && _catalogReady) {
      final hit = CityTierCatalog.resolve(plan.building.cityName);
      plan.building.cityName =
          hit.matchedName.isEmpty ? plan.building.cityName : hit.matchedName;
      plan.building.cityTier = hit.tier;
      plan.building.cityTierSource = 'auto';
      _cityCtrl.text = plan.building.cityName;
    }
    plan.annotations.redRulerCm = double.tryParse(_redCtrl.text);
    plan.annotations.blueRulerCm = double.tryParse(_blueCtrl.text);
    final pct = double.tryParse(_storageCtrl.text);
    plan.building.storageRatioSurvey = pct == null ? null : pct / 100.0;
    plan.annotations.openConnections = _openCtrl.text
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    _applyFields();
    await _repo.save(plan);
    // I19：把当前方案城市回写为默认，供下次模板注入
    final s = await SettingsRepository().load();
    s['default_city_name'] = plan.building.cityName;
    s['city_tier_default'] = plan.building.cityTier;
    await SettingsRepository().save(s);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存到本地')));
    }
  }

  Future<void> _open3d() async {
    _applyFields();
    await _repo.save(plan);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => Viewer3dPage(plan: plan)),
    );
  }

  Future<void> _diagnose() async {
    _applyFields();
    final blockers = DiagnosisEngine.blockers(plan);
    if (blockers.isNotEmpty) {
      final needArea = blockers.any((b) => b.code == 'AREA_REQUIRED');
      final needRooms = blockers.any((b) => b.code == 'ROOMS_EMPTY');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('还不能生成诊断'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('还需：', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final b in blockers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('· ${b.message}', style: const TextStyle(height: 1.35)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (needArea) {
                  _tabs.animateTo(0);
                } else if (needRooms) {
                  _tabs.animateTo(1);
                } else {
                  _tabs.animateTo(1);
                }
              },
              child: const Text('去填写'),
            ),
          ],
        ),
      );
      return;
    }
    await _repo.save(plan);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DiagnosisReportPage(plan: plan)),
    );
  }

  Future<void> _replaceWithDemo() async {
    final demo = DemoPlans.twoBed();
    setState(() {
      plan = demo;
      _syncControllers();
    });
    await _repo.save(plan);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已载入示例方案')));
    }
  }

  @override
  void dispose() {
    // 先失焦，避免 Autocomplete/Overlay 类依赖在路由卸下时触发
    // `_dependents.isEmpty` 断言（真机 debug 红屏）。
    FocusManager.instance.primaryFocus?.unfocus();
    _tabs.dispose();
    _nameCtrl.dispose();
    _areaCtrl.dispose();
    _netCtrl.dispose();
    _roomsCtrl.dispose();
    _bathCtrl.dispose();
    _cityCtrl.dispose();
    _redCtrl.dispose();
    _blueCtrl.dispose();
    _storageCtrl.dispose();
    _openCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('编辑方案'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '基础信息'), Tab(text: '户型画布')],
          onTap: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
        actions: [
          TextButton(onPressed: _replaceWithDemo, child: const Text('示例')),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildInfo(),
          PlanCanvasPanel(
            plan: plan,
            onChanged: () => setState(() {}),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _open3d,
                  child: const Text('看 3D'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _diagnose,
                  child: const Text('保存并生成诊断'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildInfo() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: '方案名称 *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _areaCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '建筑面积 *',
            border: OutlineInputBorder(),
            suffixText: '㎡',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _roomsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '房间数 *',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _bathCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '卫生间数 *',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 不用 Autocomplete Overlay：系统深浅色切换 / 返回时易触发
        // InheritedElement `_dependents.isEmpty` 红屏；改为页内建议条。
        TextField(
          controller: _cityCtrl,
          decoration: InputDecoration(
            labelText: '城市名 *',
            border: const OutlineInputBorder(),
            helperText: _cityHint,
            helperMaxLines: 2,
          ),
          onChanged: (v) {
            setState(() {
              _citySuggestions = !_catalogReady
                  ? const []
                  : CityTierCatalog.suggest(v).take(8).toList();
            });
          },
          onEditingComplete: () {
            _onCityNameCommitted(_cityCtrl.text);
            setState(() => _citySuggestions = const []);
            FocusManager.instance.primaryFocus?.unfocus();
          },
          onSubmitted: (v) {
            _onCityNameCommitted(v);
            setState(() => _citySuggestions = const []);
          },
        ),
        if (_citySuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _citySuggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () {
                    _cityCtrl.text = s;
                    _onCityNameCommitted(s);
                    setState(() => _citySuggestions = const []);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('stage_${plan.building.familyStage}'),
          initialValue: plan.building.familyStage,
          decoration: const InputDecoration(
            labelText: '家庭阶段 *',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'single', child: Text('单身期')),
            DropdownMenuItem(value: 'newlywed', child: Text('新婚期')),
            DropdownMenuItem(value: 'parenting', child: Text('育儿期')),
            DropdownMenuItem(value: 'midlife', child: Text('中年期')),
            DropdownMenuItem(value: 'empty_nest', child: Text('空巢期')),
            DropdownMenuItem(value: 'elderly', child: Text('老年期')),
          ],
          onChanged: (v) =>
              setState(() => plan.building.familyStage = v ?? 'newlywed'),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: const Text(
            '高级选项（选填，影响诊断精度）',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          children: [
            const SizedBox(height: 4),
            TextField(
              controller: _netCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '套内面积',
                border: OutlineInputBorder(),
                suffixText: '㎡',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'tier_${plan.building.cityTier}_${plan.building.cityTierSource}',
              ),
              initialValue: plan.building.cityTier,
              decoration: InputDecoration(
                labelText: '城市级别',
                border: const OutlineInputBorder(),
                helperText: plan.building.cityTierIsManual
                    ? '已手改 · 改城市名不再自动覆盖'
                    : '可随城市名自动建议；随时可改',
              ),
              items: const [
                DropdownMenuItem(value: 'tier1', child: Text('一线')),
                DropdownMenuItem(value: 'new_tier1', child: Text('新一线')),
                DropdownMenuItem(value: 'tier2', child: Text('二线')),
                DropdownMenuItem(value: 'tier3_plus', child: Text('三四线及以下')),
              ],
              onChanged: _onCityTierManual,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _redCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '面宽视距（选填）',
                border: OutlineInputBorder(),
                suffixText: 'cm',
                helperText: '客厅最大可视距离；不做自动测',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _blueCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '进深视距（选填）',
                border: OutlineInputBorder(),
                suffixText: 'cm',
                helperText: '进深方向最大可视距离；不做自动测',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _storageCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '收纳占比估算（选填）',
                border: OutlineInputBorder(),
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _openCtrl,
              decoration: const InputDecoration(
                labelText: '开放空间标注（选填）',
                border: OutlineInputBorder(),
                helperText: '例：living-dining,kitchen-dining',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('收纳通高/集成'),
              value: plan.building.storageIntegrated,
              onChanged: (v) =>
                  setState(() => plan.building.storageIntegrated = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('展示区控制（选填）'),
              value: plan.building.displayRatioOk,
              onChanged: (v) => setState(() => plan.building.displayRatioOk = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('配色控制（选填）'),
              value: plan.building.colorSchemeOk,
              onChanged: (v) => setState(() => plan.building.colorSchemeOk = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('老人'),
              value: plan.building.hasElderly,
              onChanged: (v) => setState(() => plan.building.hasElderly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('儿童'),
              value: plan.building.hasChildren,
              onChanged: (v) => setState(() => plan.building.hasChildren = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '层高默认 280cm · 门宽默认 80cm · IN-007 承重在画布标墙',
          style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
        ),
      ],
    );
  }
}
