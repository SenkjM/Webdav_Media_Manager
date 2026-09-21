import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/android_background.dart';
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
  final _libraryNav = GlobalKey<NavigatorState>();
  final _playlistsNav = GlobalKey<NavigatorState>();
  final _networkNav = GlobalKey<NavigatorState>();
  final _downloadsNav = GlobalKey<NavigatorState>();
  int _index = 0;

  static const _settingsIndex = 4;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _TabNavigator(navigatorKey: _libraryNav, root: const LibraryScreen()),
      _TabNavigator(navigatorKey: _playlistsNav, root: const PlaylistsScreen()),
      _TabNavigator(
        navigatorKey: _networkNav,
        root: const NetworkLibraryScreen(),
      ),
      _TabNavigator(navigatorKey: _downloadsNav, root: const DownloadsScreen()),
      const SettingsScreen(),
    ];

    return RootScaffold(
      scaffoldKey: _scaffoldKey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = _activeNavKey?.currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
            return;
          }
          final rootNav = Navigator.of(context, rootNavigator: true);
          if (rootNav.canPop()) {
            rootNav.pop();
            return;
          }
          // Not on the configured home tab → return to it instead of exiting.
          final home = context.read<SettingsService>().homeTab;
          if (_index != home) {
            setState(() => _index = home);
            return;
          }
          // Root back on home: send task to background (like Home) so
          // audio_service keeps playing. Do NOT SystemNavigator.pop() — that
          // finishes the Activity and disposes AppState/player.
          moveAppToBackground();
        },
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.nearBlack,
          drawer: Drawer(
            backgroundColor: AppColors.surface,
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
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
                                Icon(
                                  Icons.library_music,
                                  color: AppColors.accent,
                                  size: 32,
                                ),
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
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Divider(color: AppColors.divider),
                        ),
                        _DrawerItem(
                          icon: Icons.info_outline,
                          label: '关于 / AGPL',
                          selected: false,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: AppColors.divider),
                  ),
                  _DrawerItem(
                    icon: Icons.exit_to_app,
                    label: '退出应用',
                    selected: false,
                    onTap: () => _confirmExit(context),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
              // Global mini bar on all main tabs except Settings.
              if (_index != _settingsIndex) const MiniPlayer(),
            ],
          ),
        ),
      ),
    );
  }

  GlobalKey<NavigatorState>? get _activeNavKey {
    return switch (_index) {
      0 => _libraryNav,
      1 => _playlistsNav,
      2 => _networkNav,
      3 => _downloadsNav,
      _ => null,
    };
  }

  void _select(int i) {
    setState(() => _index = i);
    Navigator.pop(context);
  }

  Future<void> _confirmExit(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.elevated,
        title: const Text(
          '退出应用',
          style: TextStyle(color: AppColors.onDark),
        ),
        content: const Text(
          '确定退出？播放将停止。',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '退出',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context); // close drawer
    await context.read<AudioPlayerService>().stop();
    // Actually quit: finish Activity (unlike root back → moveTaskToBack).
    await SystemNavigator.pop();
  }
}

/// Keeps tab pushes (album/artist detail, playlist detail, …) above the
/// shell mini player instead of covering the whole [HomeShell].
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.root,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return [
          MaterialPageRoute<void>(
            builder: (_) => root,
            settings: const RouteSettings(name: '/'),
          ),
        ];
      },
    );
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
