import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/diy_catalog.dart';
import 'diy_steps_page.dart';

/// Debug-only：遍历 29 个 DIY 模板（真机 F3）。
class DiyCatalogDebugPage extends StatelessWidget {
  const DiyCatalogDebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'DiyCatalogDebugPage is debug-only');
    final all = DiyCatalog.all;
    return Scaffold(
      appBar: AppBar(title: Text('DIY 模板目录（${all.length}）')),
      body: ListView.separated(
        itemCount: all.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final t = all[i];
          return ListTile(
            title: Text(t.title),
            subtitle: Text('${t.templateId} · ${t.diyLevel}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => DiyStepsPage(templateId: t.templateId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
