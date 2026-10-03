import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/webdav_item.dart';
import '../services/prefetch_cache.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';
import '../utils/image_album.dart';
import 'image_settings_screen.dart';

/// Fullscreen image viewer for the network library.
///
/// Files are downloaded with [WebDavService.downloadToFile] (WebDAV Basic +
/// User-Agent, or the cloud driver's raw URL / `openContent` path) into the
/// process prefetch cache and decoded with [Image.file]. Completed files stay
/// until the next launch wipes that cache. Nothing here joins the media
/// session, the download queue, or the music cache.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.accountId,
    required this.folderPath,
    required this.initial,
    required this.siblings,
  });

  final String accountId;
  final String folderPath;
  final WebDavItem initial;

  /// Already-listed entries from the current directory. Only images are kept.
  final List<WebDavItem> siblings;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final List<WebDavItem> _seed;
  List<WebDavItem> _album = const [];
  int _index = 0;
  bool _cacheReady = false;
  SettingsService? _settings;
  WebDavService? _webDav;
  Timer? _slide;
  int _scanGen = 0;
  bool _disposed = false;
  String? _error;
  double? _progress;
  bool _scanning = false;

  final Map<String, String> _localByRemote = {};
  final Map<String, CancelToken> _inflight = {};

  String _slideSig = '';
  String _fit = SettingsService.imageFitContain;
  int _prefetch = SettingsService.defaultImagePrefetchCount;
  bool _scan = false;

  @override
  void initState() {
    super.initState();
    _seed = imageAlbumFrom(widget.siblings, ensure: widget.initial);
    _album = List<WebDavItem>.of(_seed);
    final i = _album.indexWhere((e) => e.path == widget.initial.path);
    _index = i < 0 ? 0 : i;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareCache());
      _captureSettings(notify: false);
      _armSlideshow();
      if (_settings?.imageScanSubdirs ?? false) {
        unawaited(_scanSubdirs());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsService>();
    final webDav = context.read<WebDavService>();
    if (!identical(_settings, settings)) {
      _settings?.removeListener(_onSettings);
      _settings = settings;
      settings.addListener(_onSettings);
    }
    _webDav = webDav;
  }

  @override
  void dispose() {
    _disposed = true;
    _scanGen++;
    _slide?.cancel();
    for (final token in _inflight.values) {
      token.cancel('dispose');
    }
    _inflight.clear();
    _settings?.removeListener(_onSettings);
    // Prefetch bytes stay for this process. The next launch wipes them.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  WebDavItem? get _current =>
      _album.isEmpty || _index < 0 || _index >= _album.length
      ? null
      : _album[_index];

  void _captureSettings({required bool notify}) {
    final s = _settings;
    if (s == null) return;
    _slideSig =
        '${s.imageSlideshowEnabled}:${s.imageSlideshowIntervalSeconds}:${s.imageSlideshowLoop}';
    _fit = s.imageFit;
    _prefetch = s.imagePrefetchCount;
    _scan = s.imageScanSubdirs;
    if (notify && mounted) setState(() {});
  }

  void _onSettings() {
    final s = _settings;
    if (s == null || _disposed || !mounted) return;
    final slideSig =
        '${s.imageSlideshowEnabled}:${s.imageSlideshowIntervalSeconds}:${s.imageSlideshowLoop}';
    final slideChanged = slideSig != _slideSig;
    final fitChanged = s.imageFit != _fit;
    final prefetchChanged = s.imagePrefetchCount != _prefetch;
    final scanChanged = s.imageScanSubdirs != _scan;
    _slideSig = slideSig;
    _fit = s.imageFit;
    _prefetch = s.imagePrefetchCount;
    _scan = s.imageScanSubdirs;
    if (fitChanged || prefetchChanged) setState(() {});
    if (prefetchChanged) _syncWindow();
    if (slideChanged) _armSlideshow();
    if (!scanChanged) return;
    if (s.imageScanSubdirs) {
      unawaited(_scanSubdirs());
    } else {
      _scanGen++;
      _scanning = false;
      _applyAlbum(List<WebDavItem>.of(_seed));
    }
  }

  Future<void> _prepareCache() async {
    try {
      await PrefetchCache.root();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    _cacheReady = true;
    _syncWindow();
  }

  void _applyAlbum(List<WebDavItem> next) {
    final currentPath = _current?.path ?? widget.initial.path;
    setState(() {
      _album = next;
      if (_album.isEmpty) {
        _index = 0;
        return;
      }
      final i = _album.indexWhere((e) => e.path == currentPath);
      _index = i < 0 ? 0 : i;
      _error = null;
    });
    _syncWindow();
    _armSlideshow();
  }

  Future<void> _scanSubdirs() async {
    final gen = ++_scanGen;
    final webDav = _webDav;
    final settings = _settings;
    if (webDav == null || settings == null) return;
    setState(() => _scanning = true);
    final types = settings.fileTypes;
    final pending = <String>[_normDir(widget.folderPath)];
    final seenDirs = <String>{};
    final found = <WebDavItem>[];
    while (pending.isNotEmpty) {
      if (_disposed || gen != _scanGen) return;
      if (!(_settings?.imageScanSubdirs ?? false)) return;
      final dir = pending.removeAt(0);
      if (!seenDirs.add(dir)) continue;
      List<WebDavItem> items;
      try {
        items = await webDav.listDirectory(
          widget.accountId,
          dir,
          fileTypes: types,
        );
      } catch (_) {
        continue;
      }
      if (_disposed || gen != _scanGen) return;
      found.addAll(items.where((e) => e.isImage));
      for (final child in items) {
        if (child.isDirectory) pending.add(_normDir(child.path));
      }
    }
    if (_disposed || gen != _scanGen || !mounted) return;
    setState(() => _scanning = false);
    _applyAlbum(imageAlbumFrom([..._seed, ...found], ensure: widget.initial));
  }

  String _normDir(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path.isEmpty ? '/' : path;
  }

  void _armSlideshow() {
    _slide?.cancel();
    _slide = null;
    final s = _settings;
    if (s == null || !s.imageSlideshowEnabled || _album.length < 2) return;
    final atEnd = _index + 1 >= _album.length;
    if (atEnd && !s.imageSlideshowLoop) return;
    _slide = Timer(Duration(seconds: s.imageSlideshowIntervalSeconds), () {
      if (!mounted || _disposed) return;
      _step(1, fromTimer: true);
    });
  }

  /// [fromTimer] false is a finger tap: restart the interval, but never
  /// clear the slideshow switch.
  void _step(int delta, {required bool fromTimer}) {
    if (_album.isEmpty) return;
    var next = _index + delta;
    if (next < 0 || next >= _album.length) {
      final loop = fromTimer && (_settings?.imageSlideshowLoop ?? false);
      if (!loop) {
        if (fromTimer) {
          _slide?.cancel();
          _slide = null;
        }
        return;
      }
      next = delta > 0 ? 0 : _album.length - 1;
    }
    setState(() {
      _index = next;
      _error = null;
      _progress = null;
    });
    _syncWindow();
    _armSlideshow();
  }

  void _syncWindow() {
    if (!_cacheReady || _album.isEmpty) return;
    final n = (_settings?.imagePrefetchCount ?? _prefetch).clamp(
      SettingsService.minImagePrefetchCount,
      SettingsService.maxImagePrefetchCount,
    );
    final keep = <String>{};
    for (var d = -n; d <= n; d++) {
      final i = _index + d;
      if (i < 0 || i >= _album.length) continue;
      final item = _album[i];
      keep.add(item.path);
      unawaited(_download(item));
    }
    for (final remote in _inflight.keys.toList()) {
      if (keep.contains(remote)) continue;
      _inflight.remove(remote)?.cancel('window');
    }
    // Completed files stay after they leave the window. Only this launch's
    // startup wipe removes them.
  }

  Future<void> _download(WebDavItem item) async {
    final webDav = _webDav;
    if (webDav == null || !_cacheReady || _disposed) return;
    final existing = _localByRemote[item.path];
    if (existing != null &&
        File(existing).existsSync() &&
        File(existing).lengthSync() > 0) {
      return;
    }
    if (_inflight.containsKey(item.path)) return;
    final token = CancelToken();
    _inflight[item.path] = token;
    final dest = await PrefetchCache.file(
      bucket: 'images',
      accountId: widget.accountId,
      remotePath: item.path,
      name: item.name,
    );
    if (PrefetchCache.isComplete(dest)) {
      _localByRemote[item.path] = dest.path;
      if (!mounted || _disposed) return;
      setState(() {
        if (_current?.path == item.path) {
          _error = null;
          _progress = null;
        }
      });
      _precache(dest);
      _inflight.remove(item.path);
      return;
    }
    final part = File('${dest.path}.part');
    try {
      if (part.existsSync()) part.deleteSync();
      await webDav.downloadToFile(
        widget.accountId,
        item.path,
        part,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted || _disposed || token.isCancelled) return;
          if (_current?.path != item.path || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (_disposed || token.isCancelled) {
        if (part.existsSync()) part.deleteSync();
        return;
      }
      if (!part.existsSync() || part.lengthSync() <= 0) return;
      if (dest.existsSync()) dest.deleteSync();
      await part.rename(dest.path);
      _localByRemote[item.path] = dest.path;
      if (!mounted) return;
      setState(() {
        if (_current?.path == item.path) {
          _error = null;
          _progress = null;
        }
      });
      _precache(dest);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        if (part.existsSync()) {
          try {
            part.deleteSync();
          } catch (_) {}
        }
        return;
      }
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {}
      }
      if (!mounted || _disposed) return;
      if (_current?.path == item.path) {
        final text = e.toString();
        setState(() {
          _error = text.length > 180 ? text.substring(0, 180) : text;
          _progress = null;
        });
      }
    } finally {
      if (identical(_inflight[item.path], token)) {
        _inflight.remove(item.path);
      }
    }
  }

  void _precache(File file) {
    if (!mounted || _disposed) return;
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final provider = ResizeImage(
      FileImage(file),
      width: (size.width * dpr).round().clamp(1, 8192),
      height: (size.height * dpr).round().clamp(1, 8192),
    );
    unawaited(() async {
      try {
        await precacheImage(provider, context);
      } catch (_) {}
    }());
  }

  Future<void> _openSettings() async {
    // The settings page is a normal scaffold. Immersive mode would hide its
    // status bar, so restore system UI while it is on top and go back after.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ImageSettingsScreen()));
    if (!mounted || _disposed) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mq = MediaQuery.of(context);
    final gesture = mq.systemGestureInsets;
    final pad = mq.padding;
    final left = gesture.left > pad.left ? gesture.left : pad.left;
    final right = gesture.right > pad.right ? gesture.right : pad.right;
    final top = gesture.top > pad.top ? gesture.top : pad.top;
    final bottom = gesture.bottom > pad.bottom ? gesture.bottom : pad.bottom;
    final current = _current;
    final local = current == null ? null : _localByRemote[current.path];
    final file = local == null ? null : File(local);
    final dpr = mq.devicePixelRatio;
    final cacheW = (mq.size.width * dpr).round().clamp(1, 8192);
    final cacheH = (mq.size.height * dpr).round().clamp(1, 8192);
    final fit = _fit == SettingsService.imageFitCover
        ? BoxFit.cover
        : BoxFit.contain;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (current == null)
            Center(
              child: Text(
                l10n.imageViewerEmpty,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          else if (_error == null && file != null && file.existsSync())
            Image.file(
              file,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: cacheW,
              cacheHeight: cacheH,
              gaplessPlayback: true,
              errorBuilder: (_, error, _) {
                final message = error.toString();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _error != null) return;
                  if (_current?.path != current.path) return;
                  setState(() {
                    _error = message.length > 180
                        ? message.substring(0, 180)
                        : message;
                  });
                });
                return const SizedBox.expand();
              },
            )
          else if (_error == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(left, top, right, bottom),
            child: Row(
              children: [
                Expanded(
                  child: _zone(
                    l10n.imageViewerPrevious,
                    () => _step(-1, fromTimer: false),
                  ),
                ),
                Expanded(
                  child: _zone(l10n.imageViewerOpenSettings, _openSettings),
                ),
                Expanded(
                  child: _zone(
                    l10n.imageViewerNext,
                    () => _step(1, fromTimer: false),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null && current != null)
            Center(child: _failure(l10n, current)),
          Positioned(
            left: left + 4,
            top: top + 4,
            child: IconButton(
              tooltip: l10n.close,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          Positioned(
            left: left + 56,
            right: right + 8,
            top: top + 12,
            child: IgnorePointer(
              child: Text(
                current == null
                    ? ''
                    : '${current.name}  ${l10n.imageViewerCount(_index + 1, _album.length)}'
                          '${_scanning ? '  ${l10n.imageScanningSubdirs}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
          if (_progress != null)
            Positioned(
              left: left,
              right: right,
              bottom: bottom,
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          Positioned(
            left: left + 16,
            right: right + 16,
            bottom: bottom + 12,
            child: IgnorePointer(
              child: Text(
                l10n.imageViewerGestureHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zone(String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _failure(AppLocalizations l10n, WebDavItem item) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.imageLoadFailed(_error ?? item.name),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final path = _localByRemote.remove(item.path);
                if (path != null) {
                  final cached = File(path);
                  if (cached.existsSync()) {
                    try {
                      cached.deleteSync();
                    } catch (_) {}
                  }
                }
                setState(() => _error = null);
                unawaited(_download(item));
              },
              child: Text(l10n.imageViewerRetry),
            ),
          ],
        ),
      ),
    );
  }
}
