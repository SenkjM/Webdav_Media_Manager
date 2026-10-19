// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/emby_connection.dart';
import '../services/emby_connection_store.dart';
import '../services/emby_media_client.dart';
import '../widgets/mini_player.dart';
import 'home_shell.dart';

/// Emby / Jellyfin 媒体库主屏幕（只读/浏览侧）。
///
/// 包含：连接 picker、Views 列表 → 条目浏览（音乐视图有 专辑/艺术家/歌曲
/// 分段切换），连接管理入口。与 WebDAV 账号/AccountsService 完全隔离。
class EmbyMediaScreen extends StatefulWidget {
  const EmbyMediaScreen({super.key});

  @override
  State<EmbyMediaScreen> createState() => _EmbyMediaScreenState();
}

class _EmbyMediaScreenState extends State<EmbyMediaScreen> {
  late final EmbyMediaClient _client;
  EmbyConnection? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<EmbyConnectionStore>();
      _client = EmbyMediaClient(store: store);
      if (store.connections.isNotEmpty && _selected == null) {
        setState(() => _selected = store.connections.first);
      }
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EmbyConnectionStore>();

    // Re-lookup selected connection from store to pick up userId updates after login.
    if (_selected != null) {
      final refreshed = store.connections
          .where((c) => c.id == _selected!.id)
          .firstOrNull;
      if (refreshed == null) {
        // Connection was deleted — fall back to first or null.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selected = store.connections.isNotEmpty
                  ? store.connections.first
                  : null;
            });
          }
        });
      } else if (refreshed != _selected ||
          refreshed.userId != _selected!.userId) {
        // userId or other fields updated; re-bind without rebuilding BrowseView key.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selected = refreshed);
        });
      }
    }

    // Auto-select newly added connection when nothing is selected.
    if (_selected == null && store.connections.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selected == null) {
          setState(() => _selected = store.connections.last);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: _buildConnectionPicker(context, store),
        actions: [
          if (store.connections.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.manage_accounts_outlined),
              tooltip: '管理连接',
              onPressed: () => _showConnectionList(context, store),
            ),
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: '添加连接',
            onPressed: () =>
                _showConnectionEditor(context, store, conn: null),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: store.isEmpty
                ? _buildEmptyState(context, store)
                : _selected == null
                    ? _buildNoSelection()
                    : _EmbyBrowseView(
                        key: ValueKey(_selected!.id),
                        connection: _selected!,
                        client: _client,
                      ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  // ── connection picker ─────────────────────────────────────────────────────

  Widget _buildConnectionPicker(
    BuildContext context,
    EmbyConnectionStore store,
  ) {
    if (store.isEmpty) return const Text('Emby');
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selected?.id,
        icon: const Icon(Icons.arrow_drop_down),
        isExpanded: true,
        items: store.connections
            .map(
              (c) => DropdownMenuItem<String>(
                value: c.id,
                child: Text(c.label, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (id) {
          if (id == null) return;
          setState(() =>
              _selected = store.connections.firstWhere((c) => c.id == id));
        },
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  // ── empty / no-selection states ───────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context, EmbyConnectionStore store) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_circle_outlined,
                size: 72, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text('还没有 Emby 连接',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '点击右上角"+"添加一个 Emby / Jellyfin 服务器',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_link),
              label: const Text('添加连接'),
              onPressed: () =>
                  _showConnectionEditor(context, store, conn: null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSelection() =>
      const Center(child: Text('请在顶部选择一个连接'));

  // ── connection list dialog ────────────────────────────────────────────────

  Future<void> _showConnectionList(
    BuildContext context,
    EmbyConnectionStore store,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Consumer<EmbyConnectionStore>(
        builder: (context2, s, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('已保存的连接',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ...s.connections.map(
                (c) => ListTile(
                  leading: Icon(_authIcon(c.authMode)),
                  title: Text(c.label),
                  subtitle: Text(c.baseUrl, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '编辑',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showConnectionEditor(context, s, conn: c);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除',
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _confirmDelete(context, s, c);
                        },
                      ),
                    ],
                  ),
                  selected: _selected?.id == c.id,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    EmbyConnectionStore store,
    EmbyConnection conn,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('确定删除「${conn.label}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteConnection(conn.id);
  }

  // ── connection editor ─────────────────────────────────────────────────────

  Future<void> _showConnectionEditor(
    BuildContext context,
    EmbyConnectionStore store, {
    required EmbyConnection? conn,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) =>
          _ConnectionEditorDialog(store: store, existing: conn),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static IconData _authIcon(EmbyAuthMode mode) => switch (mode) {
        EmbyAuthMode.password => Icons.lock_outlined,
        EmbyAuthMode.apiKey => Icons.vpn_key_outlined,
      };
}

// ─── Browse view ───────────────────────────────────────────────────────────

/// 针对一条连接的浏览视图（Views 列表 → 条目浏览）。
class _EmbyBrowseView extends StatefulWidget {
  const _EmbyBrowseView({
    super.key,
    required this.connection,
    required this.client,
  });

  final EmbyConnection connection;
  final EmbyMediaClient client;

  @override
  State<_EmbyBrowseView> createState() => _EmbyBrowseViewState();
}

class _EmbyBrowseViewState extends State<_EmbyBrowseView> {
  List<EmbyView>? _views;
  bool _loading = false;
  String? _error;

  // Navigation: null = top-level Views; non-null = browsing inside a view.
  EmbyView? _currentView;
  String? _currentParentId; // null = view root

  // Music sub-tab: 0=专辑 1=艺术家 2=歌曲
  int _musicTab = 0;

  @override
  void initState() {
    super.initState();
    _loadViews();
  }

  Future<void> _loadViews() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final views =
          await widget.client.getViews(widget.connection);
      if (mounted) setState(() => _views = views);
    } on EmbyApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '发生未知错误：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enterView(EmbyView view) {
    setState(() {
      _currentView = view;
      _currentParentId = null;
      _musicTab = 0;
    });
  }

  void _enterFolder(EmbyItem folder) {
    setState(() => _currentParentId = folder.id);
  }

  void _goBack() {
    if (_currentParentId != null) {
      setState(() => _currentParentId = null);
    } else {
      setState(() => _currentView = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError(context);

    final view = _currentView;
    if (view == null) {
      return _buildViewsList(context);
    }
    if (view.collectionType == 'music') {
      return _buildMusicView(context, view);
    }
    return _buildItemsList(
      context,
      parentId: _currentParentId ?? view.id,
      onBack: _goBack,
    );
  }

  Widget _buildViewsList(BuildContext context) {
    final views = _views;
    if (views == null || views.isEmpty) {
      return _buildEmptyViewState(context);
    }
    return ListView.builder(
      itemCount: views.length,
      itemBuilder: (ctx, i) {
        final v = views[i];
        return ListTile(
          leading: Icon(_viewIcon(v.collectionType)),
          title: Text(v.name),
          subtitle: v.collectionType != null
              ? Text(v.collectionType!, style: const TextStyle(fontSize: 12))
              : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _enterView(v),
        );
      },
    );
  }

  Widget _buildMusicView(BuildContext context, EmbyView view) {
    return Column(
      children: [
        _buildBackBar(context, view.name),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('专辑')),
              ButtonSegment(value: 1, label: Text('艺术家')),
              ButtonSegment(value: 2, label: Text('歌曲')),
            ],
            selected: {_musicTab},
            onSelectionChanged: (s) =>
                setState(() => _musicTab = s.first),
          ),
        ),
        Expanded(
          child: _MusicSubView(
            key: ValueKey('${widget.connection.id}/${view.id}/$_musicTab'),
            connection: widget.connection,
            client: widget.client,
            view: view,
            tabIndex: _musicTab,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList(
    BuildContext context, {
    required String parentId,
    required VoidCallback onBack,
  }) {
    return Column(
      children: [
        _buildBackBar(context, '返回'),
        Expanded(
          child: _ItemsView(
            key: ValueKey('${widget.connection.id}/$parentId'),
            connection: widget.connection,
            client: widget.client,
            parentId: parentId,
            onFolderTap: _enterFolder,
            onItemTap: _onItemTap,
          ),
        ),
      ],
    );
  }

  Widget _buildBackBar(BuildContext context, String label) {
    return Row(
      children: [
        BackButton(onPressed: _goBack),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  void _onItemTap(BuildContext context, EmbyItem item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.displayName,
                  style: Theme.of(ctx).textTheme.titleMedium),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(item.subtitle,
                    style: TextStyle(
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurfaceVariant)),
              ],
              if (item.overview.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.overview,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('播放（未接入）'),
                // TODO(99 §21): 接入现有播放栈后启用。
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: scheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: _loadViews,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyViewState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 12),
          const Text('暂无媒体库'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
            onPressed: _loadViews,
          ),
        ],
      ),
    );
  }

  static IconData _viewIcon(String? collectionType) => switch (collectionType) {
        'music' => Icons.music_note_outlined,
        'movies' => Icons.movie_outlined,
        'tvshows' => Icons.tv_outlined,
        'books' => Icons.menu_book_outlined,
        'homevideos' => Icons.home_outlined,
        'playlists' => Icons.queue_music_outlined,
        _ => Icons.folder_outlined,
      };
}

// ─── Music sub-view ────────────────────────────────────────────────────────

class _MusicSubView extends StatefulWidget {
  const _MusicSubView({
    super.key,
    required this.connection,
    required this.client,
    required this.view,
    required this.tabIndex,
  });

  final EmbyConnection connection;
  final EmbyMediaClient client;
  final EmbyView view;
  final int tabIndex; // 0=专辑 1=艺术家 2=歌曲

  @override
  State<_MusicSubView> createState() => _MusicSubViewState();
}

class _MusicSubViewState extends State<_MusicSubView> {
  List<EmbyItem> _items = [];
  bool _loading = false;
  String? _error;
  bool _hasMore = true;
  int _startIndex = 0;
  static const _limit = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items = [];
        _startIndex = 0;
        _hasMore = true;
      }
    });
    try {
      final EmbyItemsPage page;
      switch (widget.tabIndex) {
        case 1: // 艺术家
          page = await widget.client.getArtists(
            widget.connection,
            widget.view.id,
            startIndex: _startIndex,
            limit: _limit,
          );
        case 2: // 歌曲
          page = await widget.client.getItems(
            widget.connection,
            parentId: widget.view.id,
            includeItemTypes: ['Audio'],
            recursive: true,
            startIndex: _startIndex,
            limit: _limit,
          );
        default: // 0 = 专辑
          page = await widget.client.getMusicAlbums(
            widget.connection,
            widget.view.id,
            startIndex: _startIndex,
            limit: _limit,
          );
      }
      if (mounted) {
        setState(() {
          _items = [..._items, ...page.items];
          _startIndex += page.items.length;
          _hasMore = page.hasMore;
        });
      }
    } on EmbyApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '发生未知错误：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _buildError(context);
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            const Text('暂无条目'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
              onPressed: () => _load(reset: true),
            ),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 200 && _hasMore && !_loading) {
          _load();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.72,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= _items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _EmbyItemCard(
            item: _items[i],
            connection: widget.connection,
          );
        },
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: scheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: () => _load(reset: true),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Items view (generic browse) ───────────────────────────────────────────

class _ItemsView extends StatefulWidget {
  const _ItemsView({
    super.key,
    required this.connection,
    required this.client,
    required this.parentId,
    required this.onFolderTap,
    required this.onItemTap,
  });

  final EmbyConnection connection;
  final EmbyMediaClient client;
  final String parentId;
  final void Function(EmbyItem) onFolderTap;
  final void Function(BuildContext, EmbyItem) onItemTap;

  @override
  State<_ItemsView> createState() => _ItemsViewState();
}

class _ItemsViewState extends State<_ItemsView> {
  List<EmbyItem> _items = [];
  bool _loading = false;
  String? _error;
  bool _hasMore = true;
  int _startIndex = 0;
  static const _limit = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.client.getItems(
        widget.connection,
        parentId: widget.parentId,
        startIndex: _startIndex,
        limit: _limit,
      );
      if (mounted) {
        setState(() {
          _items = [..._items, ...page.items];
          _startIndex += page.items.length;
          _hasMore = page.hasMore;
        });
      }
    } on EmbyApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '发生未知错误：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: scheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: () {
                setState(() {
                  _items = [];
                  _hasMore = true;
                  _startIndex = 0;
                  _error = null;
                });
                _load();
              },
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            const Text('暂无条目'),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 200 && _hasMore && !_loading) _load();
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.72,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= _items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = _items[i];
          if (item.isFolder) {
            return _EmbyItemCard(
              item: item,
              connection: widget.connection,
              onTap: () => widget.onFolderTap(item),
            );
          }
          return _EmbyItemCard(
            item: item,
            connection: widget.connection,
            onTap: () => widget.onItemTap(ctx, item),
          );
        },
      ),
    );
  }
}

// ─── Item card ─────────────────────────────────────────────────────────────

class _EmbyItemCard extends StatelessWidget {
  const _EmbyItemCard({
    required this.item,
    required this.connection,
    this.onTap,
  });

  final EmbyItem item;
  final EmbyConnection connection;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tag = item.primaryImageTag;
    final imgUrl = tag != null
        ? EmbyMediaClient.imageUrl(connection, item.id,
            maxWidth: 200, tag: tag)
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imgUrl != null
                  ? Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx2, err, st) => _placeholder(scheme),
                    )
                  : _placeholder(scheme),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            item.isFolder
                ? Icons.folder_outlined
                : Icons.image_outlined,
            color: scheme.outlineVariant,
          ),
        ),
      );
}

// ─── Connection editor dialog ───────────────────────────────────────────────

class _ConnectionEditorDialog extends StatefulWidget {
  const _ConnectionEditorDialog({
    required this.store,
    required this.existing,
  });

  final EmbyConnectionStore store;
  final EmbyConnection? existing;

  @override
  State<_ConnectionEditorDialog> createState() =>
      _ConnectionEditorDialogState();
}

class _ConnectionEditorDialogState extends State<_ConnectionEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _apiKey;
  late EmbyAuthMode _authMode;
  bool _obscurePassword = true;
  bool _obscureApiKey = true;
  bool _saving = false;
  String? _saveError;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _label = TextEditingController(text: c?.label ?? '');
    _baseUrl = TextEditingController(text: c?.baseUrl ?? '');
    _username = TextEditingController(text: c?.username ?? '');
    _password = TextEditingController();
    _apiKey = TextEditingController();
    _authMode = c?.authMode ?? EmbyAuthMode.password;
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? '编辑连接' : '添加连接'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 名称
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: '连接名称',
                  hintText: '我的 Emby',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '名称不能为空' : null,
              ),
              const SizedBox(height: 12),
              // 地址
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://host:8096',
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return '地址不能为空';
                  final url = v.trim();
                  if (!url.startsWith('http://') &&
                      !url.startsWith('https://')) {
                    return '地址需以 http:// 或 https:// 开头';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // 认证方式
              DropdownButtonFormField<EmbyAuthMode>(
                initialValue: _authMode,
                decoration: const InputDecoration(labelText: '认证方式'),
                items: const [
                  DropdownMenuItem(
                    value: EmbyAuthMode.password,
                    child: Text('用户名 + 密码'),
                  ),
                  DropdownMenuItem(
                    value: EmbyAuthMode.apiKey,
                    child: Text('API Key'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _authMode = v);
                },
              ),
              // 用户名（password 或 apiKey 可选）
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: '用户名'),
                validator: (v) {
                  if (_authMode == EmbyAuthMode.password &&
                      (v == null || v.trim().isEmpty)) {
                    return '用户名不能为空';
                  }
                  return null;
                },
              ),
              // 密码（password 模式）
              if (_authMode == EmbyAuthMode.password) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText:
                        widget.existing == null ? '密码' : '密码（留空则保留原密码）',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ],
              // API Key（apiKey 模式）
              if (_authMode == EmbyAuthMode.apiKey) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKey,
                  obscureText: _obscureApiKey,
                  decoration: InputDecoration(
                    labelText: widget.existing == null
                        ? 'API Key'
                        : 'API Key（留空则保留原 Key）',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureApiKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                    ),
                  ),
                ),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveError!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.existing == null ? '添加' : '保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final label = _label.text.trim();
      final baseUrl =
          _baseUrl.text.trim().replaceAll(RegExp(r'/$'), '');
      final username = _username.text.trim();
      final password = _password.text;
      final apiKey = _apiKey.text.trim();

      if (widget.existing == null) {
        final conn = EmbyConnection(
          label: label,
          baseUrl: baseUrl,
          authMode: _authMode,
          username: username,
        );
        await widget.store.addConnection(
          conn,
          password: password.isNotEmpty ? password : null,
          apiKey: apiKey.isNotEmpty ? apiKey : null,
        );
        // password 模式：立即尝试登录以获取 userId，存 token。
        if (_authMode == EmbyAuthMode.password &&
            password.isNotEmpty) {
          try {
            final client =
                EmbyMediaClient(store: widget.store);
            await client.authenticate(conn, password: password);
          } on EmbyApiException catch (e) {
            if (mounted) setState(() => _saveError = '测试连接失败：${e.message}');
            return;
          }
        }
      } else {
        final conn = widget.existing!.copyWith(
          label: label,
          baseUrl: baseUrl,
          authMode: _authMode,
          username: username,
        );
        await widget.store.updateConnection(
          conn,
          password:
              password.isNotEmpty ? password : null,
          apiKey: apiKey.isNotEmpty ? apiKey : null,
        );
        // Re-authenticate / resolve userId after credential change.
        final client = EmbyMediaClient(store: widget.store);
        final fresh = widget.store.connections.firstWhere(
          (c) => c.id == conn.id,
          orElse: () => conn,
        );
        try {
          if (_authMode == EmbyAuthMode.password && password.isNotEmpty) {
            await client.authenticate(fresh, password: password);
          } else if (_authMode == EmbyAuthMode.apiKey) {
            // Trigger GET /Users resolution if userId is empty.
            await client.getViews(fresh);
          }
        } on EmbyApiException catch (e) {
          if (mounted) setState(() => _saveError = '测试连接失败：${e.message}');
          return;
        }
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

