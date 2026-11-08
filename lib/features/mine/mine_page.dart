import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../acceptance/acceptance_page.dart';
import '../diy/diy_catalog_debug_page.dart';
import '../legal/legal_pages.dart';
import '../safety/safety_page.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final _repo = SettingsRepository();
  final _plans = PlanRepository();
  final _checklist = ChecklistRepository();
  var _offset = true;
  var _tier = 'tier2';
  var _wallOpacity = 0.35;
  var _planCount = 0;
  var _listCount = 0;
  var _bytes = 0;
  var _visionBase = '';
  var _visionKey = '';
  var _visionModel = 'gpt-4o';
  var _visionGenModel = '';

  @override
  void initState() {
    super.initState();
    _repo.load().then((s) {
      if (!mounted) return;
      setState(() {
        _offset = s['city_offset_enabled'] as bool? ?? true;
        _tier = s['city_tier_default'] as String? ?? 'tier2';
        final v = s['wall_opacity'];
        final n = v is num ? v.toDouble() : double.tryParse('$v');
        if (n != null) _wallOpacity = n.clamp(0.02, 1.0);
        _visionBase = s['vision_api_base'] as String? ?? '';
        _visionKey = s['vision_api_key'] as String? ?? '';
        _visionModel = s['vision_api_model'] as String? ?? 'gpt-4o';
        _visionGenModel = s['vision_gen_model'] as String? ?? '';
      });
    });
    _refreshDataStats();
  }

  Future<void> _refreshDataStats() async {
    final pc = await _plans.count();
    final lc = await _checklist.count();
    final pb = await _plans.approxBytes();
    final cb = await _checklist.approxBytes();
    if (!mounted) return;
    setState(() {
      _planCount = pc;
      _listCount = lc;
      _bytes = pb + cb;
    });
  }

  Future<void> _persist() async {
    final s = await _repo.load();
    s['city_tier_default'] = _tier;
    s['city_offset_enabled'] = _offset;
    s['wall_opacity'] = _wallOpacity;
    s['vision_api_base'] = _visionBase.trim();
    s['vision_api_key'] = _visionKey.trim();
    s['vision_api_model'] =
        _visionModel.trim().isEmpty ? 'gpt-4o' : _visionModel.trim();
    s['vision_gen_model'] = _visionGenModel.trim();
    // I19：保留已有 default_city_name，不再每次写死「成都」
    await _repo.save(s);
  }

  String get _wallOpacityLabel {
    if ((_wallOpacity - 1.0).abs() < 0.02) return '不透明';
    if ((_wallOpacity - 0.08).abs() < 0.02) return '近隐';
    return '半透明';
  }

  String get _sizeLabel {
    if (_bytes < 1024) return '$_bytes B';
    if (_bytes < 1024 * 1024) {
      return '${(_bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(_bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _exportAll() async {
    final plansText = await _plans.exportAllText();
    final listText = await _checklist.exportText();
    final text = '$plansText\n\n========\n\n$listText';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: '轻装家 · 本地数据导出'),
    );
  }

  Future<void> _copySummary() async {
    final text =
        '方案 $_planCount 个 · 清单 $_listCount 条 · 约 $_sizeLabel\n（详细 JSON 请用「导出全部」）';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制数据摘要')),
    );
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部本地数据？'),
        content: Text(
          '将删除 $_planCount 个方案与 $_listCount 条清单，不可恢复。设置项保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _plans.deleteAll();
    await _checklist.clearAll();
    await _refreshDataStats();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除本地方案与清单')),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _sectionCard(List<Widget> children) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.brandSoft,
                    child: Text(
                      AppConstants.appName.substring(0, 1),
                      style: const TextStyle(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '轻装家用户',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '本地模式 · 数据保存在本机',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _sectionHeader('诊断设置'),
          _sectionCard([
            ListTile(
              title: const Text('城市级别默认'),
              subtitle: Text('${_tierLabel(_tier)} · 影响诊断标准'),
              trailing: DropdownButton<String>(
                value: _tier,
                items: const [
                  DropdownMenuItem(value: 'tier1', child: Text('一线')),
                  DropdownMenuItem(value: 'new_tier1', child: Text('新一线')),
                  DropdownMenuItem(value: 'tier2', child: Text('二线')),
                  DropdownMenuItem(value: 'tier3_plus', child: Text('三四线')),
                ],
                onChanged: (v) async {
                  setState(() => _tier = v ?? 'tier2');
                  await _persist();
                },
              ),
            ),
            SwitchListTile(
              title: const Text('城市级别微调'),
              subtitle: const Text('默认开启，±2 级浮动'),
              value: _offset,
              onChanged: (v) async {
                setState(() => _offset = v);
                await _persist();
              },
            ),
          ]),
          _sectionHeader('3D 设置'),
          _sectionCard([
            ListTile(
              title: const Text('墙体透明度'),
              subtitle: Text('默认$_wallOpacityLabel · 减轻四面墙遮挡'),
              trailing: DropdownButton<double>(
                value: (_wallOpacity - 1.0).abs() < 0.02
                    ? 1.0
                    : (_wallOpacity - 0.08).abs() < 0.02
                        ? 0.08
                        : 0.35,
                items: const [
                  DropdownMenuItem(value: 0.35, child: Text('半透明')),
                  DropdownMenuItem(value: 0.08, child: Text('近隐')),
                  DropdownMenuItem(value: 1.0, child: Text('不透明')),
                ],
                onChanged: (v) async {
                  setState(() => _wallOpacity = v ?? 0.35);
                  await _persist();
                },
              ),
            ),
          ]),
          _sectionHeader('拍照识图 / 改造（可选联网）'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Key/Base 可复用；理解模型与生成模型应分开配置（留空生成模型=回退理解模型，属降级）。'
              'P1 为弱约束风格迁移，不是强结构控图。',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textSecondary.withValues(alpha: 0.95),
              ),
            ),
          ),
          _sectionCard([
            ListTile(
              title: const Text('视觉 API Base URL'),
              subtitle: Text(
                _visionBase.isEmpty ? '未配置 · 本地示意' : _visionBase,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final ctrl = TextEditingController(text: _visionBase);
                final v = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('视觉 API Base'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: 'https://api.openai.com',
                        helperText:
                            '可填根地址、…/v3，或完整 …/chat/completions（方舟等）',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                ctrl.dispose();
                if (v == null) return;
                setState(() => _visionBase = v.trim());
                await _persist();
              },
            ),
            ListTile(
              title: const Text('API Key'),
              subtitle: Text(
                _visionKey.isEmpty ? '未配置' : '已保存（${#visionKey} 位）',
              ),
              trailing: const Icon(Icons.vpn_key_outlined),
              onTap: () async {
                final ctrl = TextEditingController(text: _visionKey);
                final v = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('视觉 API Key'),
                    content: TextField(
                      controller: ctrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        hintText: 'sk-…',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                ctrl.dispose();
                if (v == null) return;
                setState(() => _visionKey = v.trim());
                await _persist();
              },
            ),
            ListTile(
              title: const Text('理解模型（识图 / P1 结构 JSON）'),
              subtitle: Text(_visionModel),
              trailing: const Icon(Icons.smart_toy_outlined),
              onTap: () async {
                final ctrl = TextEditingController(text: _visionModel);
                final v = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('理解模型'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: 'gpt-4o',
                        helperText:
                            '出 JSON：户型识图、改造结构理解。≠ 出图模型',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                ctrl.dispose();
                if (v == null) return;
                setState(() =>
                    _visionModel = v.trim().isEmpty ? 'gpt-4o' : v.trim());
                await _persist();
              },
            ),
            ListTile(
              title: const Text('生成模型（P1 出图，可选）'),
              subtitle: Text(
                _visionGenModel.isEmpty
                    ? '未单独配置 · 回退理解模型（Key≠Model 降级）'
                    : _visionGenModel,
              ),
              trailing: const Icon(Icons.image_outlined),
              onTap: () async {
                final ctrl = TextEditingController(text: _visionGenModel);
                final v = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('生成模型'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        hintText: '留空=回退理解模型',
                        helperText:
                            'Key/Base 可复用；模型名建议与理解模型分开（出图能力）',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctrl.text),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                ctrl.dispose();
                if (v == null) return;
                setState(() => _visionGenModel = v.trim());
                await _persist();
              },
            ),
          ]),
          _sectionHeader('工具'),
          _sectionCard([
            ListTile(
              title: const Text('业主验收 25 条'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AcceptancePage()),
                );
              },
            ),
            ListTile(
              title: const Text('安全自查'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SafetyPage()),
                );
              },
            ),
          ]),
          _sectionHeader('数据管理'),
          _sectionCard([
            ListTile(
              title: const Text('本地占用'),
              subtitle: Text(
                '方案 $_planCount 个 · 清单 $_listCount 条 · 约 $_sizeLabel',
              ),
              trailing: IconButton(
                tooltip: '刷新',
                onPressed: _refreshDataStats,
                icon: const Icon(Icons.refresh),
              ),
            ),
            ListTile(
              title: const Text('导出全部'),
              subtitle: const Text('分享方案摘要 + JSON 与清单文本'),
              trailing: const Icon(Icons.ios_share_outlined),
              onTap: _exportAll,
            ),
            ListTile(
              title: const Text('复制摘要'),
              trailing: const Icon(Icons.copy_outlined),
              onTap: _copySummary,
            ),
            ListTile(
              title: const Text('清除全部本地数据'),
              subtitle: const Text('删除方案与清单，设置保留'),
              trailing: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              onTap: _clearAll,
            ),
          ]),
          _sectionHeader('关于'),
          _sectionCard([
            ListTile(
              title: const Text('隐私政策'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownAssetPage(
                      title: '隐私政策',
                      assetPath: 'assets/legal/privacy_policy.md',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              title: const Text('权限与数据说明'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MarkdownAssetPage(
                      title: '权限说明',
                      assetPath: 'assets/legal/permissions_summary.md',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              title: const Text('关于与免责'),
              subtitle: const Text('版本 ${AppConstants.appVersion}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            if (kDebugMode)
              ListTile(
                title: const Text('DIY 模板目录（调试）'),
                subtitle: const Text('真机 F3：遍历 29 模板'),
                trailing: const Icon(Icons.bug_report_outlined),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DiyCatalogDebugPage(),
                    ),
                  );
                },
              ),
          ]),
          const SizedBox(height: 16),
          const Text(
            '默认无埋点 · 不上云 · cn.qingzhuangjia.app',
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }

  String _tierLabel(String t) => switch (t) {
        'tier1' => '一线',
        'new_tier1' => '新一线',
        'tier3_plus' => '三四线',
        _ => '二线',
      };
}
