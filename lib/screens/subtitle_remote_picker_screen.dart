import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/webdav_item.dart';
import '../services/webdav_service.dart';
import '../theme/app_theme.dart';
import '../utils/subtitle_sidecar.dart';

/// Browse one account and pick a subtitle file. There is no account switcher:
/// the caller passes the account that is already playing.
class SubtitleRemotePickerScreen extends StatefulWidget {
  const SubtitleRemotePickerScreen({
    super.key,
    required this.accountId,
    required this.initialDirectory,
  });

  final String accountId;
  final String initialDirectory;

  @override
  State<SubtitleRemotePickerScreen> createState() =>
      _SubtitleRemotePickerScreenState();
}

class _SubtitleRemotePickerScreenState
    extends State<SubtitleRemotePickerScreen> {
  late String _directory;
  List<WebDavItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _directory = canonicalDirectory(widget.initialDirectory);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<WebDavService>().listDirectory(
        widget.accountId,
        _directory,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openDirectory(WebDavItem item) {
    _directory = canonicalDirectory(item.path);
    _load();
  }

  void _up() {
    if (_directory == '/') return;
    _directory = videoParentDirectory(_directory);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = [
      for (final item in _items)
        if (item.isDirectory || _isSubtitleFile(item)) item,
    ];
    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(
        title: Text(l10n.videoSubtitleImportRemote),
        actions: [
          if (_directory != '/')
            IconButton(
              tooltip: l10n.back,
              onPressed: _up,
              icon: const Icon(Icons.arrow_upward),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    _directory,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      l10n.videoSubtitleNone,
                      style: const TextStyle(color: AppColors.secondaryText),
                    ),
                  ),
                for (final item in entries)
                  ListTile(
                    leading: Icon(
                      item.isDirectory
                          ? Icons.folder_outlined
                          : Icons.subtitles_outlined,
                    ),
                    title: Text(item.name),
                    onTap: () {
                      if (item.isDirectory) {
                        _openDirectory(item);
                      } else {
                        Navigator.of(context).pop(item);
                      }
                    },
                  ),
              ],
            ),
    );
  }

  bool _isSubtitleFile(WebDavItem item) {
    final dot = item.name.lastIndexOf('.');
    if (dot <= 0) return false;
    final ext = item.name.substring(dot + 1).toLowerCase();
    return subtitleSidecarExtensions.contains(ext);
  }
}
