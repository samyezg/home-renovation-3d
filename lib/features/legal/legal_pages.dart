import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../theme/app_colors.dart';

class MarkdownAssetPage extends StatefulWidget {
  const MarkdownAssetPage({
    super.key,
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;

  @override
  State<MarkdownAssetPage> createState() => _MarkdownAssetPageState();
}

class _MarkdownAssetPageState extends State<MarkdownAssetPage> {
  String _text = '加载中…';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString(widget.assetPath).then((v) {
      if (mounted) setState(() => _text = v);
    }).catchError((_) {
      if (mounted) setState(() => _text = '无法加载文档');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SelectableText(
            _text,
            style: const TextStyle(
              height: 1.45,
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            AppConstants.disclaimer,
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于轻装家')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text(
            '轻装家',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4),
          Text('户型诊断与软装DIY', style: TextStyle(color: AppColors.textSecondary)),
          SizedBox(height: 16),
          Text('版本：${AppConstants.appVersion}'),
          Text('applicationId：cn.qingzhuangjia.app'),
          Text('iOS Bundle ID（预留）：cn.qingzhuangjia.app'),
          SizedBox(height: 12),
          Text('仅本地存储 · 默认无账号 · 默认无埋点'),
          SizedBox(height: 16),
          Text(AppConstants.disclaimer, style: TextStyle(height: 1.4)),
          SizedBox(height: 12),
          Text(
            '运营主体与联系邮箱请在上架前于隐私政策中替换占位字段。',
            style: TextStyle(fontSize: 12, color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}
