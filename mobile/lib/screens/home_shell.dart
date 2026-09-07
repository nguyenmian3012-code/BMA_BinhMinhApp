import 'dart:async';

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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  int _unreadAnnouncements = 0;
  int _announcementsVersion = 0;
  bool _checkingAnnouncements = false;
  Timer? _announcementTimer;

  late final List<Widget> _primaryPages = [
    OverviewScreen(repository: widget.repository),
    QualityScreen(repository: widget.repository),
    AttendanceScreen(repository: widget.repository),
    ProfileScreen(repository: widget.repository),
  ];

  static const _titles = [
    'Nhà máy',
    'Chất lượng',
    'Chấm công',
    'Cá nhân',
    'Thông báo',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAnnouncementPolling();
  }

  @override
  void dispose() {
    _announcementTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAnnouncementPolling();
      if (_index == 4) {
        _reloadAnnouncements();
      } else {
        _refreshUnreadAnnouncements();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _announcementTimer?.cancel();
    }
  }

  void _startAnnouncementPolling() {
    _announcementTimer?.cancel();
    _announcementTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnreadAnnouncements(),
    );
  }

  Future<void> _refreshUnreadAnnouncements() async {
    if (_checkingAnnouncements) return;
    _checkingAnnouncements = true;
    try {
      final response = await widget.repository.announcements();
      final count = announcementUnreadCount(response.data);
      if (!mounted || count == _unreadAnnouncements) return;
      setState(() {
        _unreadAnnouncements = count;
        if (_index == 4) _announcementsVersion++;
      });
    } on Object {
      // Keep the last badge count while offline.
    } finally {
      _checkingAnnouncements = false;
    }
  }

  void _reloadAnnouncements() {
    if (!mounted) return;
    setState(() => _announcementsVersion++);
  }

  void _selectPage(int value) {
    setState(() {
      _index = value;
      if (value == 4) _announcementsVersion++;
    });
  }

  void _setUnreadAnnouncements(int count) {
    if (!mounted || count == _unreadAnnouncements) return;
    setState(() => _unreadAnnouncements = count);
  }

  Widget _announcementIcon(IconData icon) => Badge(
    isLabelVisible: _unreadAnnouncements > 0,
    label: Text(
      _unreadAnnouncements > 99 ? '99+' : '$_unreadAnnouncements',
    ),
    child: Icon(icon),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      ..._primaryPages,
      AnnouncementsScreen(
        key: ValueKey(_announcementsVersion),
        repository: widget.repository,
        onUnreadCountChanged: _setUnreadAnnouncements,
      ),
    ];

    return Scaffold(
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
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectPage,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.factory_outlined),
            selectedIcon: Icon(Icons.factory),
            label: 'Nhà máy',
          ),
          const NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'KCS',
          ),
          const NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Công',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cá nhân',
          ),
          NavigationDestination(
            icon: _announcementIcon(Icons.notifications_outlined),
            selectedIcon: _announcementIcon(Icons.notifications),
            label: 'Tin',
          ),
        ],
      ),
    );
  }
}
