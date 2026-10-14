// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/image_viewer_page.dart';
import '../models/page_turn_direction.dart';
import '../models/webdav_item.dart';
import '../services/prefetch_cache.dart';
import '../services/settings_service.dart';
import '../services/cache_service.dart';
import '../services/manga_cover_writer.dart';
import '../services/manga_library_service.dart';
import '../services/webdav_service.dart';
import '../utils/app_snack.dart';
import '../utils/image_album.dart';
import '../widgets/manga_set_cover_dialog.dart';
import 'image_settings_screen.dart';
import '../utils/directory_walk.dart';

/// Fullscreen image / manga page viewer.
///
/// Network library and manga library share this screen. Downloads use
/// [WebDavService.downloadToFile] into [PrefetchCache]; CBZ pages may already
/// have a local path. Center tap opens a controls sheet (not a page jump);
/// left/right edges and horizontal swipe change pages.
class ImageViewerScreen extends StatefulWidget {
  /// Network-library folder album (keeps existing call sites).
  factory ImageViewerScreen({
    Key? key,
    required String accountId,
    required String folderPath,
    required WebDavItem initial,
    required List<WebDavItem> siblings,
    ValueChanged<int>? onPageChanged,
    String? title,
  }) {
    final album = imageAlbumFrom(siblings, ensure: initial);
    final pages = [for (final e in album) ImageViewerPage.fromWebDav(e)];
    final i = album.indexWhere((e) => e.path == initial.path);
    return ImageViewerScreen.pages(
      key: key,
      accountId: accountId,
      folderPath: folderPath,
      pages: pages,
      initialIndex: i < 0 ? 0 : i,
      enableSubdirScan: true,
      onPageChanged: onPageChanged,
      title: title,
    );
  }

  /// Generic page list (manga or any prepared album).
  const ImageViewerScreen.pages({
    super.key,
    required this.accountId,
    required this.pages,
    this.initialIndex = 0,
    this.folderPath = '/',
    this.enableSubdirScan = false,
    this.onPageChanged,
    this.title,
    this.mangaId,
  });

  final String accountId;
  final String folderPath;
  final List<ImageViewerPage> pages;
  final int initialIndex;
  final bool enableSubdirScan;
  final ValueChanged<int>? onPageChanged;
  final String? title;

  /// When set, viewer is manga mode: BottomSheet shows per-manga page-turn.
  final String? mangaId;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late List<ImageViewerPage> _seed;
  late List<ImageViewerPage> _album;
  late int _index;
  bool _cacheReady = false;
  SettingsService? _settings;
  WebDavService? _webDav;
  Timer? _slide;
  int _scanGen = 0;
  bool _disposed = false;
  String? _error;
  double? _progress;
  bool _scanning = false;
  bool _controlsOpen = false;
  bool _coverJob = false;

  final Map<String, String> _localById = {};
  final Map<String, CancelToken> _inflight = {};

  String _slideSig = '';
  String _fit = SettingsService.imageFitContain;
  String _globalPageTurn = PageTurnDirection.ltr;
  String? _mangaPageTurn; // null = follow global
  int _prefetch = SettingsService.defaultImagePrefetchCount;
  bool _scan = false;

  @override
  void initState() {
    super.initState();
    _seed = List<ImageViewerPage>.of(widget.pages);
    _album = List<ImageViewerPage>.of(_seed);
    _index = widget.initialIndex.clamp(
      0,
      _album.isEmpty ? 0 : _album.length - 1,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareCache());
      _captureSettings(notify: false);
      unawaited(_loadMangaPageTurn());
      _armSlideshow();
      if (widget.enableSubdirScan && (_settings?.imageScanSubdirs ?? false)) {
        unawaited(_scanSubdirs());
      }
      widget.onPageChanged?.call(_index);
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  ImageViewerPage? get _current =>
      _album.isEmpty || _index < 0 || _index >= _album.length
      ? null
      : _album[_index];

  Future<void> _loadMangaPageTurn() async {
    final id = widget.mangaId;
    if (id == null || id.isEmpty || !mounted) return;
    try {
      final mangaLib = context.read<MangaLibraryService>();
      for (final e in mangaLib.mangas) {
        if (e.id == id) {
          if (!mounted) return;
          setState(() => _mangaPageTurn = e.pageTurn);
          return;
        }
      }
    } catch (_) {}
  }

  String get _effectivePageTurn =>
      PageTurnDirection.normalize(_mangaPageTurn ?? _globalPageTurn);

  void _captureSettings({required bool notify}) {
    final s = _settings;
    if (s == null) return;
    _slideSig =
        '${s.imageSlideshowEnabled}:${s.imageSlideshowIntervalSeconds}:${s.imageSlideshowLoop}';
    _fit = s.imageFit;
    _globalPageTurn = s.imagePageTurn;
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
    final turnChanged = s.imagePageTurn != _globalPageTurn;
    final prefetchChanged = s.imagePrefetchCount != _prefetch;
    final scanChanged = s.imageScanSubdirs != _scan;
    _slideSig = slideSig;
    _fit = s.imageFit;
    _globalPageTurn = s.imagePageTurn;
    _prefetch = s.imagePrefetchCount;
    _scan = s.imageScanSubdirs;
    if (fitChanged || prefetchChanged || turnChanged) setState(() {});
    if (prefetchChanged) _syncWindow();
    if (slideChanged) _armSlideshow();
    if (!widget.enableSubdirScan || !scanChanged) return;
    if (s.imageScanSubdirs) {
      unawaited(_scanSubdirs());
    } else {
      _scanGen++;
      _scanning = false;
      _applyAlbum(List<ImageViewerPage>.of(_seed));
    }
  }

  Future<void> _prepareCache() async {
    try {
      await PrefetchCache.root();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    // Seed local paths from prepared pages (e.g. CBZ extracts).
    for (final page in _album) {
      final local = page.localPath;
      if (local != null &&
          local.isNotEmpty &&
          File(local).existsSync() &&
          File(local).lengthSync() > 0) {
        _localById[page.id] = local;
      }
    }
    _cacheReady = true;
    _syncWindow();
    if (mounted) setState(() {});
  }

  void _applyAlbum(List<ImageViewerPage> next) {
    final currentId = _current?.id;
    setState(() {
      _album = next;
      if (_album.isEmpty) {
        _index = 0;
        return;
      }
      final i = currentId == null
          ? 0
          : _album.indexWhere((e) => e.id == currentId);
      _index = i < 0 ? 0 : i;
      _error = null;
    });
    _syncWindow();
    _armSlideshow();
    widget.onPageChanged?.call(_index);
  }

  Future<void> _scanSubdirs() async {
    if (!widget.enableSubdirScan) return;
    final gen = ++_scanGen;
    final webDav = _webDav;
    final settings = _settings;
    if (webDav == null || settings == null) return;
    setState(() => _scanning = true);
    final types = settings.fileTypes;
    final walker = DirectoryWalker(
      rootPath: widget.folderPath,
      options: settings.imageScanWalkOptions,
    );
    final found = <WebDavItem>[];
    while (true) {
      if (_disposed || gen != _scanGen) return;
      if (!(_settings?.imageScanSubdirs ?? false)) return;
      final dir = walker.nextDirectory();
      if (dir == null) break;
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
      walker.acceptChildren(dir, [
        for (final child in items)
          if (child.isDirectory) child.path,
      ]);
    }
    if (_disposed || gen != _scanGen || !mounted) return;
    setState(() => _scanning = false);
    final seedItems = [
      for (final p in _seed)
        if (p.remotePath != null)
          WebDavItem(name: p.name, path: p.remotePath!, isDirectory: false),
    ];
    final ensure = seedItems.isEmpty
        ? null
        : seedItems[_index.clamp(0, seedItems.length - 1)];
    final album = ensure == null
        ? found
        : imageAlbumFrom([...seedItems, ...found], ensure: ensure);
    _applyAlbum([for (final e in album) ImageViewerPage.fromWebDav(e)]);
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

  void _turnFromEdge(int edgeDelta, {required bool fromTimer}) {
    final delta = PageTurnDirection.indexDeltaForEdge(
      edgeDelta,
      _effectivePageTurn,
    );
    _step(delta, fromTimer: fromTimer);
  }

  void _step(int delta, {required bool fromTimer}) {
    if (_album.isEmpty || _controlsOpen) return;
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
    widget.onPageChanged?.call(_index);
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
      keep.add(item.id);
      unawaited(_ensureLocal(item));
    }
    for (final id in _inflight.keys.toList()) {
      if (keep.contains(id)) continue;
      _inflight.remove(id)?.cancel('window');
    }
  }

  Future<void> _ensureLocal(ImageViewerPage item) async {
    final webDav = _webDav;
    if (!_cacheReady || _disposed) return;
    final existing = _localById[item.id];
    if (existing != null &&
        File(existing).existsSync() &&
        File(existing).lengthSync() > 0) {
      return;
    }
    final seeded = item.localPath;
    if (seeded != null &&
        seeded.isNotEmpty &&
        File(seeded).existsSync() &&
        File(seeded).lengthSync() > 0) {
      _localById[item.id] = seeded;
      if (mounted && !_disposed) {
        setState(() {
          if (_current?.id == item.id) {
            _error = null;
            _progress = null;
          }
        });
        _precache(File(seeded));
      }
      return;
    }
    // CBZ pages have no URL of their own: the page loader pulls the entry out
    // of the archive, and only for the pages inside the prefetch window.
    final lazyLoader = item.localLoader;
    final lazyPath = item.localPath;
    if (lazyLoader != null && lazyPath != null && lazyPath.isNotEmpty) {
      if (_inflight.containsKey(item.id)) return;
      final token = CancelToken();
      _inflight[item.id] = token;
      final file = File(lazyPath);
      try {
        await lazyLoader(file);
        if (_disposed || token.isCancelled) return;
        if (!file.existsSync() || file.lengthSync() <= 0) return;
        _localById[item.id] = file.path;
        if (!mounted) return;
        setState(() {
          if (_current?.id == item.id) {
            _error = null;
            _progress = null;
          }
        });
        _precache(file);
      } catch (e) {
        if (!mounted || _disposed) return;
        if (_current?.id == item.id) {
          final text = e.toString();
          setState(() {
            _error = text.length > 180 ? text.substring(0, 180) : text;
            _progress = null;
          });
        }
      } finally {
        if (identical(_inflight[item.id], token)) {
          _inflight.remove(item.id);
        }
      }
      return;
    }
    if (!item.hasRemote || webDav == null) return;
    if (_inflight.containsKey(item.id)) return;
    final token = CancelToken();
    _inflight[item.id] = token;
    final dest = await PrefetchCache.file(
      bucket: 'images',
      accountId: widget.accountId,
      remotePath: item.remotePath!,
      name: item.name,
    );
    if (PrefetchCache.isComplete(dest)) {
      _localById[item.id] = dest.path;
      if (!mounted || _disposed) return;
      setState(() {
        if (_current?.id == item.id) {
          _error = null;
          _progress = null;
        }
      });
      _precache(dest);
      _inflight.remove(item.id);
      return;
    }
    final part = File('${dest.path}.part');
    try {
      if (part.existsSync()) part.deleteSync();
      await webDav.downloadToFile(
        widget.accountId,
        item.remotePath!,
        part,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted || _disposed || token.isCancelled) return;
          if (_current?.id != item.id || total <= 0) return;
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
      _localById[item.id] = dest.path;
      if (!mounted) return;
      setState(() {
        if (_current?.id == item.id) {
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
      if (_current?.id == item.id) {
        final text = e.toString();
        setState(() {
          _error = text.length > 180 ? text.substring(0, 180) : text;
          _progress = null;
        });
      }
    } finally {
      if (identical(_inflight[item.id], token)) {
        _inflight.remove(item.id);
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

  Future<void> _openControlsSheet() async {
    if (_controlsOpen || !mounted) return;
    _controlsOpen = true;
    _slide?.cancel();
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    final mangaId = widget.mangaId;
    final mangaLib = mangaId == null || mangaId.isEmpty
        ? null
        : context.read<MangaLibraryService>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.imageViewerControls,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.imageViewerCount(_index + 1, _album.length),
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.imageFit),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: SettingsService.imageFitContain,
                            label: Text(l10n.imageFitContain),
                          ),
                          ButtonSegment(
                            value: SettingsService.imageFitCover,
                            label: Text(l10n.imageFitCover),
                          ),
                        ],
                        selected: {_fit},
                        onSelectionChanged: (s) {
                          unawaited(settings.setImageFit(s.first));
                          setState(() => _fit = s.first);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.imagePageTurnGlobal),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: PageTurnDirection.ltr,
                            label: Text(l10n.imagePageTurnLtr),
                          ),
                          ButtonSegment(
                            value: PageTurnDirection.rtl,
                            label: Text(l10n.imagePageTurnRtl),
                          ),
                        ],
                        selected: {_globalPageTurn},
                        onSelectionChanged: (s) {
                          final v = s.first;
                          unawaited(settings.setImagePageTurn(v));
                          setState(() => _globalPageTurn = v);
                          setSheet(() {});
                        },
                      ),
                      if (mangaId != null && mangaId.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(l10n.imagePageTurnManga),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: 'follow',
                              label: Text(l10n.imagePageTurnFollowGlobal),
                            ),
                            ButtonSegment(
                              value: PageTurnDirection.ltr,
                              label: Text(l10n.imagePageTurnLtr),
                            ),
                            ButtonSegment(
                              value: PageTurnDirection.rtl,
                              label: Text(l10n.imagePageTurnRtl),
                            ),
                          ],
                          selected: {
                            _mangaPageTurn == null || _mangaPageTurn!.isEmpty
                                ? 'follow'
                                : PageTurnDirection.normalize(_mangaPageTurn),
                          },
                          onSelectionChanged: (s) {
                            final v = s.first;
                            final next = v == 'follow' ? null : v;
                            setState(() => _mangaPageTurn = next);
                            setSheet(() {});
                            if (mangaLib != null) {
                              unawaited(mangaLib.setPageTurn(mangaId, next));
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.photo_outlined),
                          title: Text(l10n.mangaSetPageAsCover),
                          onTap: () async {
                            final yes = await _askSetCover(ctx);
                            if (yes != true || !mounted) return;
                            _coverJob = true;
                            _slide?.cancel();
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _applySetCover();
                          },
                        ),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.imageSlideshow),
                        value: settings.imageSlideshowEnabled,
                        onChanged: (v) {
                          unawaited(settings.setImageSlideshowEnabled(v));
                          setSheet(() {});
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.imageViewerMoreSettings),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _openFullSettings();
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.close),
                        title: Text(l10n.imageViewerClose),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _controlsOpen = false;
    if (!mounted || _disposed) return;
    if (!_coverJob) _armSlideshow();
    setState(() {});
  }


  Future<bool?> _askSetCover(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx)!;
    return showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.mangaSetPageAsCoverTitle),
          content: Text(l10n.mangaSetPageAsCoverBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(l10n.mangaSetPageAsCoverConfirm),
            ),
          ],
        ),
      ),
    );
  }

  int? _pageIndexFromId(String id, String mangaId) {
    final prefix = '$mangaId:';
    if (!id.startsWith(prefix)) return null;
    return int.tryParse(id.substring(prefix.length));
  }

  Future<String?> _coverRelFor(String mangaId, ImageViewerPage page) async {
    final fromId = _pageIndexFromId(page.id, mangaId);
    final index = fromId ?? _index;
    try {
      final pages = await context.read<MangaLibraryService>().pagesFor(mangaId);
      if (index >= 0 && index < pages.length && pages[index].relPath.isNotEmpty) {
        return pages[index].relPath;
      }
    } catch (_) {}
    final remote = page.remotePath;
    if (remote != null && remote.isNotEmpty) return remote;
    return null;
  }

  Future<List<int>?> _bytesForCover(ImageViewerPage page, CancelToken cancel) async {
    final cached = _localById[page.id];
    if (cached != null && File(cached).existsSync() && File(cached).lengthSync() > 0) {
      return File(cached).readAsBytes();
    }
    final seeded = page.localPath;
    if (seeded != null && seeded.isNotEmpty && File(seeded).existsSync() && File(seeded).lengthSync() > 0) {
      return File(seeded).readAsBytes();
    }
    if (cancel.isCancelled) return null;
    final loader = page.localLoader;
    final lazyPath = page.localPath;
    if (loader != null && lazyPath != null && lazyPath.isNotEmpty) {
      final file = File(lazyPath);
      await loader(file);
      if (cancel.isCancelled) return null;
      if (file.existsSync() && file.lengthSync() > 0) return file.readAsBytes();
      return null;
    }
    final remote = page.remotePath;
    final webDav = _webDav;
    if (remote == null || remote.isEmpty || webDav == null) return null;
    final dest = await PrefetchCache.file(
      bucket: 'images',
      accountId: widget.accountId,
      remotePath: remote,
      name: page.name,
    );
    if (PrefetchCache.isComplete(dest)) return dest.readAsBytes();
    final part = File('${dest.path}.part');
    try {
      if (part.existsSync()) part.deleteSync();
      await webDav.downloadToFile(
        widget.accountId,
        remote,
        part,
        cancelToken: cancel,
      );
      if (cancel.isCancelled) {
        if (part.existsSync()) part.deleteSync();
        return null;
      }
      if (!part.existsSync() || part.lengthSync() <= 0) return null;
      if (dest.existsSync()) dest.deleteSync();
      await part.rename(dest.path);
      _localById[page.id] = dest.path;
      return await dest.readAsBytes();
    } on DioException catch (e) {
      if (part.existsSync()) {
        try {
          part.deleteSync();
        } catch (_) {}
      }
      if (CancelToken.isCancel(e) || cancel.isCancelled) return null;
      rethrow;
    }
  }

  Future<void> _applySetCover() async {
    final mangaId = widget.mangaId;
    final page = _current;
    final l10n = AppLocalizations.of(context)!;
    if (mangaId == null || mangaId.isEmpty || page == null) {
      _coverJob = false;
      if (mounted && !_disposed) _armSlideshow();
      return;
    }
    final outcome = await showDialog<MangaCoverSetOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => MangaSetCoverDialog(
        title: l10n.mangaSetPageAsCoverWorking,
        body: l10n.mangaSetPageAsCoverWorkingBody,
        cancelLabel: l10n.cancel,
        work: (cancel) => _writeCurrentCover(mangaId, page, cancel),
      ),
    );
    _coverJob = false;
    if (!mounted || _disposed) return;
    _armSlideshow();
    switch (outcome) {
      case MangaCoverSetOutcome.done:
        AppSnack.show(context, l10n.mangaSetPageAsCoverDone);
      case MangaCoverSetOutcome.failed:
        AppSnack.show(context, l10n.mangaSetPageAsCoverFailed, error: true);
      case MangaCoverSetOutcome.cancelled:
      case null:
        break;
    }
  }

  Future<MangaCoverSetOutcome> _writeCurrentCover(
    String mangaId,
    ImageViewerPage page,
    CancelToken cancel,
  ) async {
    final rel = await _coverRelFor(mangaId, page);
    if (cancel.isCancelled) return MangaCoverSetOutcome.cancelled;
    if (rel == null || rel.isEmpty) return MangaCoverSetOutcome.failed;
    final bytes = await _bytesForCover(page, cancel);
    if (cancel.isCancelled) return MangaCoverSetOutcome.cancelled;
    if (bytes == null || bytes.isEmpty) return MangaCoverSetOutcome.failed;
    if (!mounted) return MangaCoverSetOutcome.cancelled;
    final wrote = await writeMangaCoverThumb(
      cache: context.read<CacheService>(),
      mangaId: mangaId,
      bytes: Uint8List.fromList(bytes),
      thumbSize: _settings?.coverThumbSizePx,
    );
    if (cancel.isCancelled) return MangaCoverSetOutcome.cancelled;
    if (!wrote) return MangaCoverSetOutcome.failed;
    final ok = await context.read<MangaLibraryService>().setCoverRelpath(mangaId, rel);
    if (cancel.isCancelled) return MangaCoverSetOutcome.cancelled;
    return ok ? MangaCoverSetOutcome.done : MangaCoverSetOutcome.failed;
  }

  Future<void> _openFullSettings() async {
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
    final local = current == null ? null : _localById[current.id];
    final file = local == null ? null : File(local);
    final dpr = mq.devicePixelRatio;
    final cacheW = (mq.size.width * dpr).round().clamp(1, 8192);
    final cacheH = (mq.size.height * dpr).round().clamp(1, 8192);
    final fit = _fit == SettingsService.imageFitCover
        ? BoxFit.cover
        : BoxFit.contain;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          // Swipe left (negative velocity) = right-edge intent (+1).
          if (v <= -200) {
            _turnFromEdge(1, fromTimer: false);
          } else if (v >= 200) {
            _turnFromEdge(-1, fromTimer: false);
          }
        },
        child: Stack(
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
                    if (_current?.id != current.id) return;
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
                      () => _turnFromEdge(-1, fromTimer: false),
                    ),
                  ),
                  Expanded(
                    child: _zone(
                      l10n.imageViewerControls,
                      () => unawaited(_openControlsSheet()),
                    ),
                  ),
                  Expanded(
                    child: _zone(
                      l10n.imageViewerNext,
                      () => _turnFromEdge(1, fromTimer: false),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null && current != null)
              Center(child: _failure(l10n, current)),
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
            // Immersive chrome: the only persistent overlay is the page
            // number, centred at the bottom.
            Positioned(
              left: left + 16,
              right: right + 16,
              bottom: bottom + 12,
              child: IgnorePointer(
                child: Text(
                  current == null
                      ? ''
                      : '${l10n.imageViewerCount(_index + 1, _album.length)}'
                            '${_scanning ? '  ${l10n.imageScanningSubdirs}' : ''}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
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

  Widget _failure(AppLocalizations l10n, ImageViewerPage item) {
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
                final path = _localById.remove(item.id);
                if (path != null) {
                  final cached = File(path);
                  if (cached.existsSync()) {
                    try {
                      cached.deleteSync();
                    } catch (_) {}
                  }
                }
                setState(() => _error = null);
                unawaited(_ensureLocal(item));
              },
              child: Text(l10n.imageViewerRetry),
            ),
          ],
        ),
      ),
    );
  }
}
