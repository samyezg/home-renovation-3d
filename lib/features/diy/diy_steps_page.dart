import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/diy_catalog.dart';
import '../../models/domain.dart';
import '../../services/repositories.dart';
import '../../theme/app_colors.dart';

class DiyStepsPage extends StatelessWidget {
  const DiyStepsPage({super.key, required this.templateId, this.adviceTitle});

  final String templateId;
  final String? adviceTitle;

  @override
  Widget build(BuildContext context) {
    final t = DiyCatalog.byId(templateId);
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('步骤')),
        body: const Center(child: Text('未找到模板')),
      );
    }
    final isL3 = t.diyLevel == 'L3';
    return Scaffold(
      appBar: AppBar(title: Text(t.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${t.diyLevel} · ${'★' * t.stars}${'☆' * (5 - t.stars)}'
            '${isL3 ? '' : ' · ${t.durationMin}～${t.durationMax} 分钟'}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (adviceTitle != null) ...[
            const SizedBox(height: 8),
            Text(adviceTitle!, style: const TextStyle(color: AppColors.textPrimary)),
          ],
          const SizedBox(height: 16),
          if (isL3)
            Card(
              color: const Color(0x1AB54A3F),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(DiyCatalog.l3Speech, style: const TextStyle(height: 1.45)),
              ),
            )
          else ...[
            if (t.tools.isNotEmpty)
              Text('工具：${t.tools.join('、')}', style: const TextStyle(height: 1.4)),
            if (t.materials.isNotEmpty)
              Text('材料：${t.materials.join('、')}', style: const TextStyle(height: 1.4)),
            const SizedBox(height: 8),
            const Text('步骤', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...t.steps.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${e.key + 1}. ${e.value}', style: const TextStyle(height: 1.4)),
              ),
            ),
            if (t.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '注意：${t.warnings.join('；')}',
                style: const TextStyle(color: AppColors.warning, height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await ChecklistRepository().add(
                  ChecklistLine(
                    id: 'cl_${const Uuid().v4().substring(0, 8)}',
                    category: t.listCategory,
                    title: t.title,
                    specHint: t.listSpecHint,
                    source: t.templateId,
                    price: null,
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已加入改造清单')),
                  );
                }
              },
              child: const Text('加入改造清单'),
            ),
            const SizedBox(height: 12),
            const Text(
              AppConstants.diyDisclaimer,
              style: TextStyle(fontSize: 12, color: AppColors.textDisabled, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
