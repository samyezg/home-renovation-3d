import 'package:flutter/material.dart';

import '../services/repositories.dart';
import '../theme/app_colors.dart';

/// 首次启动四 Tab 引导：三步看懂轻装家
Future<void> showFirstRunGuideIfNeeded(
  BuildContext context, {
  void Function(int tabIndex)? onStart,
}) async {
  final repo = SettingsRepository();
  final s = await repo.load();
  if (s['first_run_guide_done'] == true) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FirstRunGuideDialog(
      onSkip: () async {
        await _persistDone(repo, s);
        if (ctx.mounted) Navigator.of(ctx).pop();
      },
      onStart: () async {
        await _persistDone(repo, s);
        if (ctx.mounted) Navigator.of(ctx).pop();
        onStart?.call(0);
      },
    ),
  );
}

Future<void> _persistDone(
  SettingsRepository repo,
  Map<String, dynamic> s,
) async {
  s['first_run_guide_done'] = true;
  await repo.save(s);
}

class _FirstRunGuideDialog extends StatelessWidget {
  const _FirstRunGuideDialog({
    required this.onSkip,
    required this.onStart,
  });

  final VoidCallback onSkip;
  final VoidCallback onStart;

  static const _steps = <(String, String)>[
    ('①', '画户型'),
    ('②', '看 3D / 得诊断'),
    ('③', '改造清单'),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('三步看懂轻装家'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in _steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.$1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.$2,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: onSkip, child: const Text('跳过')),
        FilledButton(onPressed: onStart, child: const Text('开始体验')),
      ],
    );
  }
}
