import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../services/city_tier_catalog.dart';
import '../theme/app_colors.dart';

/// I16 简化录入：模板/空白选定后，只填 2~3 个字段再进画布。
/// 返回 `true` 表示确认并已写回 [plan]；`false`/null 取消。
Future<bool?> showQuickPlanBasicsSheet(
  BuildContext context,
  PlanDocument plan,
) async {
  await CityTierCatalog.ensureLoaded();
  if (!context.mounted) return null;
  final nameCtrl = TextEditingController(text: plan.meta.name);
  final areaCtrl = TextEditingController(
    text: plan.building.areaBuildM2 > 0
        ? plan.building.areaBuildM2.toStringAsFixed(
            plan.building.areaBuildM2 == plan.building.areaBuildM2.roundToDouble()
                ? 0
                : 1,
          )
        : '',
  );
  final cityCtrl = TextEditingController(text: plan.building.cityName);
  var suggestions = <String>[];

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '确认基本信息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '填好即可进画布；其余可在「基础信息」里补',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '方案名称 *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: areaCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '建筑面积 *',
                    border: OutlineInputBorder(),
                    suffixText: '㎡',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '城市 *',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setLocal(() {
                      suggestions = CityTierCatalog.suggest(v).take(6).toList();
                    });
                  },
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in suggestions)
                        ActionChip(
                          label: Text(s),
                          onPressed: () {
                            cityCtrl.text = s;
                            setLocal(() => suggestions = const []);
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final area = double.tryParse(areaCtrl.text.trim());
                    final city = cityCtrl.text.trim();
                    if (name.isEmpty || area == null || area <= 0 || city.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('请填写名称、面积与城市')),
                      );
                      return;
                    }
                    final hit = CityTierCatalog.resolve(city);
                    plan.meta.name = name;
                    plan.building.areaBuildM2 = area;
                    plan.building.cityName =
                        hit.matchedName.isEmpty ? city : hit.matchedName;
                    if (!plan.building.cityTierIsManual) {
                      plan.building.cityTier = hit.tier;
                      plan.building.cityTierSource = 'auto';
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('进入画布'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        ),
      );
    },
  );

  nameCtrl.dispose();
  areaCtrl.dispose();
  cityCtrl.dispose();
  return ok;
}
