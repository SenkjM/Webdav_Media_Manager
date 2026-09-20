import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_task.dart';
import '../models/webdav_item.dart';
import '../providers/app_state.dart';
import '../services/audio_player_service.dart';
import '../services/download_queue_service.dart';
import '../services/webdav_service.dart';
import '../widgets/track_status_chip.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final List<String> _stack = ['/'];
  List<WebDavItem> _items = [];
  bool _loading = false;
  String? _error;

  String get _path => _stack.last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final webDav = context.read<WebDavService>();
    if (!webDav.isConnected) {
      setState(() {
        _error = '请先在「设置」中配置 WebDAV';
        _items = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await webDav.listDirectory(_path);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _items = [];
      });
    }
  }

  void _enterDir(WebDavItem item) {
    _stack.add(item.path);
    _load();
  }

  void _goUp() {
    if (_stack.length <= 1) return;
    _stack.removeLast();
    _load();
  }

  Future<void> _onTapFile(WebDavItem item) async {
    final downloads = context.read<DownloadQueueService>();
    final player = context.read<AudioPlayerService>();
    final audios = _items.where((e) => e.isAudio).toList();
    final playlist = audios
        .map(
          (e) => TrackInfo(
            remotePath: e.path,
            fileName: e.name,
          ),
        )
        .toList();
    final track = TrackInfo(remotePath: item.path, fileName: item.name);

    // If not ready, enqueue (non-blocking for navigation) then play when ready.
    final existing = downloads.taskForRemote(item.path);
    final app = context.read<AppState>();
    final cached = await app.cache.localPathIfCached(item.path);
    if (!mounted) return;
    if (cached == null &&
        (existing == null ||
            existing.status == DownloadStatus.failed ||
            existing.status == DownloadStatus.cancelled)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入下载队列：${item.name}')),
      );
    }
    await player.playTrack(track, playlist: playlist);
  }

  Future<void> _enqueueOnly(WebDavItem item) async {
    final downloads = context.read<DownloadQueueService>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('排队下载：${item.name}')),
    );
    // Fire-and-forget — must not block navigation.
    downloads.enqueue(item.path, fileName: item.name).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadQueueService>();
    final player = context.watch<AudioPlayerService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览'),
        leading: _stack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goUp,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(downloads, player),
    );
  }

  Widget _buildBody(DownloadQueueService downloads, AudioPlayerService player) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('空目录'));
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        if (item.isDirectory) {
          return ListTile(
            leading: const Icon(Icons.folder, color: Colors.amber),
            title: Text(item.name),
            subtitle: const Text('目录'),
            onTap: () => _enterDir(item),
          );
        }
        if (!item.isAudio) {
          return ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(item.name),
            subtitle: Text(item.size != null ? _fmtSize(item.size!) : '文件'),
            enabled: false,
          );
        }

        final task = downloads.taskForRemote(item.path);
        final state = downloads.uiStateFor(
          item.path,
          playingRemotePath: player.currentRemotePath,
        );
        // Undownloaded: filename/path only — no ID3.
        return ListTile(
          leading: Icon(
            state == TrackUiState.playing
                ? Icons.equalizer
                : Icons.audiotrack,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(item.name),
          subtitle: Text(item.path),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TrackStatusChip(
                state: state,
                progress: task?.status == DownloadStatus.active
                    ? task?.progress
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.download_for_offline_outlined),
                tooltip: '仅下载',
                onPressed: () => _enqueueOnly(item),
              ),
            ],
          ),
          onTap: () => _onTapFile(item),
        );
      },
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

extension on Future {
  void ignore() {}
}
