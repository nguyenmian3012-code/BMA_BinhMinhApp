import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/bma_repository.dart';
import 'announcements_screen.dart';
import 'attendance_screen.dart';
import 'overview_screen.dart';
import 'profile_screen.dart';
import 'quality_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.state, required this.repository, super.key});

  final AppState state;
  final BmaRepository repository;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final List<Widget> _pages = [
    OverviewScreen(repository: widget.repository),
    QualityScreen(repository: widget.repository),
    AttendanceScreen(repository: widget.repository),
    ProfileScreen(repository: widget.repository),
    AnnouncementsScreen(repository: widget.repository),
  ];

  static const _titles = ['Nhà máy', 'Chất lượng', 'Chấm công', 'Cá nhân', 'Thông báo'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_titles[_index]),
      actions: [
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: widget.state.logout,
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.factory_outlined), selectedIcon: Icon(Icons.factory), label: 'Nhà máy'),
        NavigationDestination(icon: Icon(Icons.science_outlined), selectedIcon: Icon(Icons.science), label: 'KCS'),
        NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'Công'),
        NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Cá nhân'),
        NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Tin'),
      ],
    ),
  );
}
