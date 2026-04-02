import 'package:flutter/material.dart';
import '../core/updater/update_dialog.dart';
import 'mode_select_screen.dart';
import 'history_screen.dart';

/// 하단 네비게이션 쉘 (모드 선택 + 이력)
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  final _screens = const [
    ModeSelectScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 앱 시작 후 1.5초 뒤 업데이트 체크 (UI 로딩 후)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        UpdateDialog.checkAndShow(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF151926),
          border: Border(top: BorderSide(color: Color(0xFF1E2235), width: 0.5)),
        ),
        child: NavigationBar(
          backgroundColor: const Color(0xFF151926),
          indicatorColor: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.square_foot_outlined, color: Colors.grey),
              selectedIcon: Icon(Icons.square_foot, color: Color(0xFF4FC3F7)),
              label: '측정',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined, color: Colors.grey),
              selectedIcon: Icon(Icons.history, color: Color(0xFF4FC3F7)),
              label: '이력',
            ),
          ],
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
    );
  }
}
