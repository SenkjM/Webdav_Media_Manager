import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'about_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';
import 'network_library_screen.dart';
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
      const NetworkLibraryScreen(),
      const DownloadsScreen(),
      const SettingsScreen(),
    ];

    return RootScaffold(
      scaffoldKey: _scaffoldKey,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'WebDAV 音乐播放器',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.library_music),
                  title: const Text('音乐库'),
                  selected: _index == 0,
                  onTap: () => _select(0),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('网络库'),
                  selected: _index == 1,
                  onTap: () => _select(1),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('下载队列'),
                  selected: _index == 2,
                  onTap: () => _select(2),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('设置'),
                  selected: _index == 3,
                  onTap: () => _select(3),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 / AGPL'),
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
