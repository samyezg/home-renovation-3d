import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/catalogs.dart';
import '../../data/diy_catalog.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../diy/diy_steps_page.dart';

class AcceptancePage extends StatefulWidget {
  const AcceptancePage({super.key});

  @override
  State<AcceptancePage> createState() => _AcceptancePageState();
}

class _AcceptancePageState extends State<AcceptancePage> {
  final _repo = ProgressRepository();
  Map<String, String> _states = {};

  @override
  void initState() {
    super.initState();
    _repo.loadStates('acceptance').then((v) {
      if (mounted) setState(() => _states = v);
    });
  }

  Future<void> _set(String id, String v) async {
    setState(() => _states[id] = v);
    await _repo.saveStates('acceptance', _states);
  }

  @override
  Widget build(BuildContext context) {
    final items = AcceptanceCatalog.items;
    final done = items.where((e) {
      final s = _states[e.id];
      return s != null && s.isNotEmpty && s != 'unanswered';
    }).length;
    final sections = <String, List<dynamic>>{};
    for (final i in items) {
      sections.putIfAbsent(i.section, () => []).add(i);
    }

    return Scaffold(
      appBar: AppBar(title: Text('业主验收 · $done/${items.length}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in sections.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                entry.key,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            ...entry.value.map((item) {
              final st = _states[item.id] ?? 'unanswered';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.id} ${item.title}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.standard,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('通过'),
                            selected: st == 'pass',
                            onSelected: (_) => _set(item.id, 'pass'),
                          ),
                          ChoiceChip(
                            label: const Text('不通过'),
                            selected: st == 'fail',
                            onSelected: (_) => _set(item.id, 'fail'),
                          ),
                          ChoiceChip(
                            label: const Text('不适用'),
                            selected: st == 'na',
                            onSelected: (_) => _set(item.id, 'na'),
                          ),
                        ],
                      ),
                      if (st == 'fail') ...[
                        const SizedBox(height: 6),
                        Text(
                          '建议：${item.failHint}',
                          style: const TextStyle(color: AppColors.warning, height: 1.35),
                        ),
                        if (item.failTypeId != null)
                          TextButton(
                            onPressed: () {
                              final t = DiyCatalog.byType(item.failTypeId!);
                              if (t == null) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DiyStepsPage(templateId: t.templateId),
                                ),
                              );
                            },
                            child: const Text('查看相关指引'),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          const Text(
            AppConstants.acceptanceDisclaimer,
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}
