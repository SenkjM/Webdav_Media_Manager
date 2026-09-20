import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import 'about_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'network_library_screen.dart';
import 'playlists_screen.dart';
import 'settings_screen.dart';

/// Provides [openDrawer] to nested page AppBars.
class RootScaffold extends InheritedWidget {
  const RootScaffold({
    super.key,
    required this.scaffoldKey,
    required super.child,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;

  static void openDrawer(BuildContext context) {
    final root = context.dependOnInheritedWidgetOfExactType<RootScaffold>();
    root?.scaffoldKey.currentState?.openDrawer();
  }

  @override
  bool updateShouldNotify(RootScaffold oldWidget) =>
      scaffoldKey != oldWidget.scaffoldKey;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const LibraryScreen(),
      const PlaylistsScreen(),
      const NetworkLibraryScreen(),
      const DownloadsScreen(),
      const SettingsScreen(),
    ];

    return RootScaffold(
      scaffoldKey: _scaffoldKey,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.nearBlack,
        drawer: Drawer(
          backgroundColor: AppColors.surface,
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Container(
                  height: 140,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  decoration: const BoxDecoration(
                    color: AppColors.elevated,
                    border: Border(
                      bottom: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: const Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.library_music, color: AppColors.accent, size: 32),
                        SizedBox(height: 12),
                        Text(
                          'WebDAV 音乐播放器',
                          style: TextStyle(
                            color: AppColors.onDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _DrawerItem(
                  icon: Icons.library_music,
                  label: '音乐库',
                  selected: _index == 0,
                  onTap: () => _select(0),
                ),
                _DrawerItem(
                  icon: Icons.queue_music,
                  label: '歌单',
                  selected: _index == 1,
                  onTap: () => _select(1),
                ),
                _DrawerItem(
                  icon: Icons.cloud_outlined,
                  label: '网络库',
                  selected: _index == 2,
                  onTap: () => _select(2),
                ),
                _DrawerItem(
                  icon: Icons.download_outlined,
                  label: '下载队列',
                  selected: _index == 3,
                  onTap: () => _select(3),
                ),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  selected: _index == 4,
                  onTap: () => _select(4),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(color: AppColors.divider),
                ),
                _DrawerItem(
                  icon: Icons.info_outline,
                  label: '关于 / AGPL',
                  selected: false,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  void _select(int i) {
    setState(() => _index = i);
    Navigator.pop(context);
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          icon,
          color: selected ? AppColors.accent : AppColors.secondaryText,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.onDark,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        selected: selected,
        selectedTileColor: AppColors.accent.withValues(alpha: 0.14),
        onTap: onTap,
      ),
    );
  }
}

/// Menu button that opens the root drawer.
class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: '菜单',
      onPressed: () => RootScaffold.openDrawer(context),
    );
  }
}
