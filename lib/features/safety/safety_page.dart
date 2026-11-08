import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/catalogs.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';
import '../diy/diy_steps_page.dart';

class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key, this.familyStage});

  final String? familyStage;

  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  final _repo = ProgressRepository();
  Map<String, String> _states = {};

  @override
  void initState() {
    super.initState();
    _repo.loadStates('safety').then((v) {
      if (mounted) setState(() => _states = v);
    });
  }

  Future<void> _set(String id, String v) async {
    setState(() => _states[id] = v);
    await _repo.saveStates('safety', _states);
  }

  @override
  Widget build(BuildContext context) {
    final items = SafetyCatalog.items;
    final yes = items.where((e) => _states[e.id] == 'yes').length;
    final answered = items.where((e) {
      final s = _states[e.id];
      return s == 'yes' || s == 'no' || s == 'na';
    }).length;
    final stage = widget.familyStage;
    final stageTip = stage == 'empty_nest' || stage == 'elderly';

    return Scaffold(
      appBar: AppBar(title: Text('安全自查 · $answered/${items.length}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(SafetyCatalog.intro, style: const TextStyle(height: 1.4)),
          if (stageTip) ...[
            const SizedBox(height: 8),
            const Text(
              '您标注的家庭阶段可能更需要关注通行与防滑，可花两分钟做完下面的安全自查。',
              style: TextStyle(color: AppColors.brand, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          if (answered == items.length)
            Card(
              color: AppColors.brandSoft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  SafetyCatalog.scoreMessage(yes),
                  style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final st = _states[item.id] ?? 'unanswered';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                title: Text('${item.id} ${item.shortTitle}'),
                subtitle: Text(item.question, maxLines: 2, overflow: TextOverflow.ellipsis),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Text(item.help, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('是'),
                        selected: st == 'yes',
                        onSelected: (_) => _set(item.id, 'yes'),
                      ),
                      ChoiceChip(
                        label: const Text('否'),
                        selected: st == 'no',
                        onSelected: (_) => _set(item.id, 'no'),
                      ),
                      ChoiceChip(
                        label: const Text('不适用'),
                        selected: st == 'na',
                        onSelected: (_) => _set(item.id, 'na'),
                      ),
                    ],
                  ),
                  if (st == 'no') ...[
                    const SizedBox(height: 6),
                    Text(item.noHint, style: const TextStyle(color: AppColors.warning)),
                    if (item.id == 'SF-05' || item.id == 'SF-08')
                      TextButton(
                        onPressed: () {
                          final tid = item.id == 'SF-08' ? 'T-L1-SLIP-01' : 'T-L1-PLANT-01';
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DiyStepsPage(templateId: tid),
                            ),
                          );
                        },
                        child: const Text('看 L1 软措施步骤'),
                      ),
                    if (item.id == 'SF-03')
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DiyStepsPage(templateId: 'T-L3-DOOR-01'),
                            ),
                          );
                        },
                        child: const Text('了解为何需专业'),
                      ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            AppConstants.safetyDisclaimer,
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}
