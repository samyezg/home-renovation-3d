import 'package:flutter/material.dart';
import '../features/checklist/checklist_page.dart';
import '../features/home/home_page.dart';
import '../features/mine/mine_page.dart';
import '../features/plan/plan_page.dart';
import '../theme/app_colors.dart';
import '../widgets/first_run_guide.dart';

/// V1 新手标准布局：底 Tab ≤4
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomePage(),
    PlanPage(),
    ChecklistPage(),
    MinePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showFirstRunGuideIfNeeded(
        context,
        onStart: (tab) => setState(() => _index = tab),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppColors.brand),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppColors.brand),
            label: '方案',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist, color: AppColors.brand),
            label: '清单',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.brand),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
