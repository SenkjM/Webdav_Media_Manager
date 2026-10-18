// Copyright (C) 2026 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/openlist_connection.dart';
import '../services/openlist_connection_store.dart';
import '../services/openlist_media_client.dart';
import '../widgets/mini_player.dart';
import 'home_shell.dart';

// ─── Tab configuration ────────────────────────────────────────────────────

const _kMediaTypes = ['video', 'music', 'image', 'book'];
const _kTabLabels = ['视频', '音乐', '图片', '书籍'];
const _kTabIcons = [
  Icons.movie_outlined,
  Icons.music_note_outlined,
  Icons.photo_outlined,
  Icons.menu_book_outlined,
];

/// OpenList 媒体库主屏幕（只读/浏览侧）。
///
/// 包含：连接 picker、四 Tab（视频/音乐/图片/书籍）、连接管理入口。
/// 与 WebDAV 账号/AccountsService 完全隔离。
class OpenListMediaScreen extends StatefulWidget {
  const OpenListMediaScreen({super.key});

  @override
  State<OpenListMediaScreen> createState() => _OpenListMediaScreenState();
}

class _OpenListMediaScreenState extends State<OpenListMediaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final OpenListMediaClient _client;
  OpenListConnection? _selected;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabLabels.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<OpenListConnectionStore>();
      _client = OpenListMediaClient(store: store);
      if (store.connections.isNotEmpty && _selected == null) {
        setState(() => _selected = store.connections.first);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OpenListConnectionStore>();

    // Sync selected connection when list changes externally.
    if (_selected != null &&
        !store.connections.any((c) => c.id == _selected!.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selected =
                store.connections.isNotEmpty ? store.connections.first : null;
          });
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
        bottom: store.isEmpty
            ? null
            : TabBar(
                controller: _tabController,
                tabs: List.generate(
                  _kTabLabels.length,
                  (i) => Tab(
                    icon: Icon(_kTabIcons[i]),
                    text: _kTabLabels[i],
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: store.isEmpty
                ? _buildEmptyState(context, store)
                : _selected == null
                    ? _buildNoSelection()
                    : TabBarView(
                        controller: _tabController,
                        children: List.generate(
                          _kMediaTypes.length,
                          (i) => _MediaTabView(
                            key: ValueKey('${_selected!.id}/${_kMediaTypes[i]}'),
                            connection: _selected!,
                            mediaType: _kMediaTypes[i],
                            client: _client,
                          ),
                        ),
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
    OpenListConnectionStore store,
  ) {
    if (store.isEmpty) {
      return const Text('OpenList');
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selected?.id,
        icon: const Icon(Icons.arrow_drop_down),
        isExpanded: true,
        items: store.connections
            .map(
              (c) => DropdownMenuItem<String>(
                value: c.id,
                child: Text(
                  c.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (id) {
          if (id == null) return;
          final conn = store.connections.firstWhere((c) => c.id == id);
          setState(() => _selected = conn);
        },
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  // ── empty / no-selection states ───────────────────────────────────────────

  Widget _buildEmptyState(
    BuildContext context,
    OpenListConnectionStore store,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_circle_outlined,
              size: 72,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有 OpenList 连接',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '点击右上角"+"添加一个 OpenList 服务器',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add_link),
              label: const Text('添加连接'),
              onPressed: () => _showConnectionEditor(context, store, conn: null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSelection() {
    return const Center(child: Text('请在顶部选择一个连接'));
  }

  // ── connection list dialog ─────────────────────────────────────────────────

  Future<void> _showConnectionList(
    BuildContext context,
    OpenListConnectionStore store,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return Consumer<OpenListConnectionStore>(
          builder: (_, s, child) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    '已保存的连接',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                ...s.connections.map(
                  (c) => ListTile(
                    leading: Icon(_authIcon(c.authMode)),
                    title: Text(c.label),
                    subtitle: Text(
                      c.baseUrl,
                      overflow: TextOverflow.ellipsis,
                    ),
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
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    OpenListConnectionStore store,
    OpenListConnection conn,
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
            child: Text(
              '删除',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await store.deleteConnection(conn.id);
    }
  }

  // ── connection editor ─────────────────────────────────────────────────────

  Future<void> _showConnectionEditor(
    BuildContext context,
    OpenListConnectionStore store, {
    required OpenListConnection? conn,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) =>
          _ConnectionEditorDialog(store: store, existing: conn),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  static IconData _authIcon(OpenListAuthMode mode) => switch (mode) {
        OpenListAuthMode.guest => Icons.no_accounts_outlined,
        OpenListAuthMode.jwt => Icons.lock_outlined,
        OpenListAuthMode.siteToken => Icons.vpn_key_outlined,
      };
}

// ─── Media tab ─────────────────────────────────────────────────────────────

class _MediaTabView extends StatefulWidget {
  const _MediaTabView({
    super.key,
    required this.connection,
    required this.mediaType,
    required this.client,
  });

  final OpenListConnection connection;
  final String mediaType;
  final OpenListMediaClient client;

  @override
  State<_MediaTabView> createState() => _MediaTabViewState();
}

class _MediaTabViewState extends State<_MediaTabView>
    with AutomaticKeepAliveClientMixin {
  OpenListMediaPage? _page;
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.client.listMedia(
        widget.connection,
        widget.mediaType,
      );
      if (mounted) setState(() => _page = page);
    } on OpenListApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '发生未知错误：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError(context);
    }
    final page = _page;
    if (page == null || page.isEmpty) {
      return _buildEmpty(context);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.72,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: page.items.length,
        itemBuilder: (ctx, i) => _MediaCard(item: page.items[i]),
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
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          const Text('暂无条目'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
            onPressed: _load,
          ),
        ],
      ),
    );
  }
}

// ─── Media card ────────────────────────────────────────────────────────────

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item});
  final OpenListMediaItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTap(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.cover.isNotEmpty
                  ? Image.network(
                      item.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stackTrace) => _placeholder(scheme),
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
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

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined, color: scheme.outlineVariant),
      ),
    );
  }

  void _onTap(BuildContext context) {
    // Phase 2：接入播放栈。当前仅展示信息。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(item.displayName),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ─── Connection editor dialog ───────────────────────────────────────────────

class _ConnectionEditorDialog extends StatefulWidget {
  const _ConnectionEditorDialog({
    required this.store,
    required this.existing,
  });

  final OpenListConnectionStore store;
  final OpenListConnection? existing;

  @override
  State<_ConnectionEditorDialog> createState() =>
      _ConnectionEditorDialogState();
}

class _ConnectionEditorDialogState extends State<_ConnectionEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _siteToken;
  late OpenListAuthMode _authMode;
  bool _useHashLogin = false;
  bool _obscurePassword = true;
  bool _obscureSiteToken = true;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _label = TextEditingController(text: c?.label ?? '');
    _baseUrl = TextEditingController(text: c?.baseUrl ?? '');
    _username = TextEditingController(text: c?.username ?? '');
    _password = TextEditingController();
    _siteToken = TextEditingController();
    _authMode = c?.authMode ?? OpenListAuthMode.guest;
    _useHashLogin = c?.useHashLogin ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    _siteToken.dispose();
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
              // ── 名称 ──────────────────────────────────
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: '连接名称',
                  hintText: '我的 OpenList',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '名称不能为空' : null,
              ),
              const SizedBox(height: 12),
              // ── 地址 ──────────────────────────────────
              TextFormField(
                controller: _baseUrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://192.168.1.100:5244',
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
              // ── 认证模式 ───────────────────────────────
              DropdownButtonFormField<OpenListAuthMode>(
                initialValue: _authMode,
                decoration: const InputDecoration(labelText: '认证方式'),
                items: const [
                  DropdownMenuItem(
                    value: OpenListAuthMode.guest,
                    child: Text('访客（无需登录）'),
                  ),
                  DropdownMenuItem(
                    value: OpenListAuthMode.jwt,
                    child: Text('用户名 + 密码（JWT）'),
                  ),
                  DropdownMenuItem(
                    value: OpenListAuthMode.siteToken,
                    child: Text('站点令牌（Token）'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _authMode = v);
                },
              ),
              // ── JWT 字段 ───────────────────────────────
              if (_authMode == OpenListAuthMode.jwt) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: (v) {
                    if (_authMode == OpenListAuthMode.jwt &&
                        (v == null || v.trim().isEmpty)) {
                      return '用户名不能为空';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: widget.existing == null ? '密码' : '密码（留空则保留原密码）',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('预散列密码'),
                  subtitle: const Text(
                    '开启后客户端先 SHA-256 散列，使用 /hash 端点',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _useHashLogin,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _useHashLogin = v),
                ),
              ],
              // ── Site Token 字段 ──────────────────────
              if (_authMode == OpenListAuthMode.siteToken) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _siteToken,
                  obscureText: _obscureSiteToken,
                  decoration: InputDecoration(
                    labelText: widget.existing == null
                        ? '站点令牌'
                        : '站点令牌（留空则保留原令牌）',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureSiteToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(
                        () => _obscureSiteToken = !_obscureSiteToken,
                      ),
                    ),
                  ),
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
    setState(() => _saving = true);
    try {
      final label = _label.text.trim();
      final baseUrl = _baseUrl.text.trim().trimRight().replaceAll(RegExp(r'/$'), '');
      final username = _username.text.trim();
      final password = _password.text;
      final siteToken = _siteToken.text.trim();

      if (widget.existing == null) {
        final conn = OpenListConnection(
          label: label,
          baseUrl: baseUrl,
          authMode: _authMode,
          username: username,
          useHashLogin: _useHashLogin,
        );
        await widget.store.addConnection(
          conn,
          password: password.isNotEmpty ? password : null,
          siteToken: siteToken.isNotEmpty ? siteToken : null,
        );
      } else {
        final conn = widget.existing!.copyWith(
          label: label,
          baseUrl: baseUrl,
          authMode: _authMode,
          username: username,
          useHashLogin: _useHashLogin,
        );
        await widget.store.updateConnection(
          conn,
          password: password.isNotEmpty
              ? password
              : null, // null → keep existing
          siteToken: _authMode == OpenListAuthMode.siteToken
              ? (siteToken.isNotEmpty ? siteToken : null)
              : '',
        );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
