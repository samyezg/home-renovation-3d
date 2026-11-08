import 'package:flutter/material.dart';
import 'shell/main_shell.dart';
import 'theme/app_theme.dart';

class QingZhuangJiaApp extends StatelessWidget {
  const QingZhuangJiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻装家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const MainShell(),
    );
  }
}
