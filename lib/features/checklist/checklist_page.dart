import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../data/catalogs.dart';
import '../../models/domain.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../viewer3d/viewer3d_page.dart';

enum _GroupMode { room, category }

class ChecklistPage extends StatefulWidget {
  const ChecklistPage({super.key});

  @override
  State<ChecklistPage> createState() => _ChecklistPageState();
}

class _ChecklistPageState extends State<ChecklistPage> {
  final _repo = ChecklistRepository();
  late Future<List<ChecklistLine>> _future;
  var _groupMode = _GroupMode.room;

  @override
  void initState() {
    super.initState();
    _future = _repo.load();
  }

  void _reload() => setState(() => _future = _repo.load());

  String _displayTitle(ChecklistLine e) {
    if (e.skuId != null && e.skuId!.isNotEmpty) {
      return SceneCatalog.labelOf(e.skuId!);
    }
    final t = e.title.trim();
    if (t.isEmpty) return t;
    final labeled = SceneCatalog.labelOf(t);
    if (labeled != t) return labeled;
    return t;
  }

  Future<void> _editLine(ChecklistLine e) async {
    final qtyCtrl = TextEditingController(text: '${e.qty}');
    final titleCtrl = TextEditingController(text: e.title);
    final roomCtrl = TextEditingController(text: e.roomHint ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑条目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: '标题（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roomCtrl,
              decoration: const InputDecoration(
                labelText: '房间（可选）',
                hintText: '如：客厅、主卧',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '数量',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? e.qty;
    e.qty = qty < 1 ? 1 : qty;
    final nextTitle = titleCtrl.text.trim();
    if (nextTitle.isNotEmpty) e.title = nextTitle;
    final room = roomCtrl.text.trim();
    e.roomHint = room.isEmpty ? null : room;
    await _repo.add(e);
    _reload();
  }

  Map<String, List<ChecklistLine>> _groupByCategory(List<ChecklistLine> items) {
    final map = <String, List<ChecklistLine>>{};
    for (final e in items) {
      final key = e.category.trim().isEmpty ? '其他' : e.category;
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  Map<String, List<ChecklistLine>> _groupByRoom(List<ChecklistLine> items) {
    final map = <String, List<ChecklistLine>>{};
    for (final e in items) {
      final hint = e.roomHint?.trim() ?? '';
      final key = hint.isEmpty ? '未指定' : hint;
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('清单'),
        actions: [
          TextButton(
            onPressed: () async {
              final text = await _repo.exportText();
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板')),
                );
              }
            },
            child: const Text('导出'),
          ),
        ],
      ),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '完成诊断后可生成改造清单',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '也可在 3D 中添加模块后写入清单',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const Viewer3dPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.view_in_ar_outlined),
                      label: const Text('去 3D 添加模块'),
                    ),
                  ],
                ),
              ),
            );
          }

          final groups = _groupMode == _GroupMode.room
              ? _groupByRoom(items)
              : _groupByCategory(items);
          final keys = groups.keys.toList()
            ..sort((a, b) {
              if (a == '未指定') return 1;
              if (b == '未指定') return -1;
              if (a == '其他') return 1;
              if (b == '其他') return -1;
              return a.compareTo(b);
            });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  const Text(
                    '本地草稿',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '共 ${items.length} 项',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  SegmentedButton<_GroupMode>(
                    segments: const [
                      ButtonSegment(
                        value: _GroupMode.room,
                        label: Text('按房间'),
                      ),
                      ButtonSegment(
                        value: _GroupMode.category,
                        label: Text('按类别'),
                      ),
                    ],
                    selected: {_groupMode},
                    onSelectionChanged: (s) {
                      setState(() => _groupMode = s.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final key in keys)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: Text(
                      key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${groups[key]!.length} 项'),
                    children: [
                      for (final e in groups[key]!)
                        ListTile(
                          title: Text(
                            '${_displayTitle(e)} ×${e.qty}',
                          ),
                          subtitle: () {
                            final parts = <String>[
                              if (_groupMode == _GroupMode.category &&
                                  e.roomHint != null &&
                                  e.roomHint!.isNotEmpty)
                                e.roomHint!,
                              if (_groupMode == _GroupMode.room &&
                                  e.category.trim().isNotEmpty)
                                e.category,
                              if (e.specHint != null && e.specHint!.isNotEmpty)
                                e.specHint!,
                            ];
                            if (parts.isEmpty) return null;
                            return Text(parts.join(' · '));
                          }(),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '编辑',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editLine(e),
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await _repo.remove(e.id);
                                  _reload();
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                AppConstants.disclaimer,
                style: TextStyle(fontSize: 11, color: AppColors.textDisabled),
              ),
            ],
          );
        },
      ),
    );
  }
}
