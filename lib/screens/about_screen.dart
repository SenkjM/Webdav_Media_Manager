import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_snack.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final _updates = AppUpdateService();
  String _versionLabel = '…';
  String _versionName = '';
  String _buildNumber = '';
  AppInstallFlavor _flavor = AppInstallFlavor.prod;
  bool _downloadInFlight = false;
  bool _packageReady = false;
  bool _channelTouched = false;
  UpdateChannel _channel = UpdateChannel.stable;

  bool get _canCheckUpdates => _flavor == AppInstallFlavor.prod;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      final flavor = flavorFromPackageName(info.packageName);
      final edition = editionFromVersion(
        versionName: info.version,
        buildNumber: info.buildNumber,
      );
      setState(() {
        _flavor = flavor;
        _packageReady = true;
        _versionName = info.version;
        _buildNumber = info.buildNumber;
        if (!_channelTouched) {
          _channel = channelForInstalledEdition(edition);
        }
        _versionLabel = switch (flavor) {
          AppInstallFlavor.dev => 'dev',
          AppInstallFlavor.sandbox => 'sandbox',
          AppInstallFlavor.prod => '${info.version}+${info.buildNumber}',
        };
      });
    });
  }

  Future<void> _checkForUpdate() async {
    final l10n = AppLocalizations.of(context)!;
    final cancel = CancelToken();
    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(l10n.aboutUpdateChecking),
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _channel == UpdateChannel.preview
                        ? l10n.aboutUpdateCheckingBodyPreview
                        : l10n.aboutUpdateCheckingBody,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancel.cancel('user cancelled update check');
                  dialogOpen = false;
                  Navigator.pop(ctx);
                },
                child: Text(l10n.cancel),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final result = await _updates.check(
        cancelToken: cancel,
        channel: _channel,
      );
      if (!mounted) return;
      if (dialogOpen) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      switch (result) {
        case UpdateCheckAvailable(:final release, :final asset):
          final download = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text(
                '${l10n.updateAvailableTitle(release.version.toString())} (${release.isPrerelease ? l10n.aboutUpdateChannelPreview : l10n.aboutUpdateChannelStable})',
              ),
              content: SingleChildScrollView(
                child: Text(
                  '${l10n.updateAvailableBody}\n\n${release.notes.trim()}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l10n.updateDownloadInstall),
                ),
              ],
            ),
          );
          if (download == true && mounted) {
            unawaited(_downloadInBackground(asset));
          }
        case UpdateCheckUpToDate(:final version):
          AppSnack.show(context, l10n.updateUpToDate(version.toString()));
        case UpdateCheckNoCompatibleApk():
          await _showError(l10n.updateNoCompatibleApk);
        case UpdateCheckUnsupported():
          await _showError(l10n.updateUnsupported);
        case UpdateCheckChannelMismatch():
          await _showError(l10n.aboutUpdateChannelMismatch);
        case UpdateCheckGithubFallback(:final latestName, :final releasesUrl):
          await _showGithubFallback(latestName, releasesUrl);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      if (mounted && dialogOpen) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) await _showError(e.toString());
    } catch (e) {
      if (mounted && dialogOpen) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) await _showError(e.toString());
    }
  }

  Future<void> _downloadInBackground(UpdateAsset asset) async {
    if (_downloadInFlight) return;
    setState(() => _downloadInFlight = true);
    try {
      final apk = await _updates.download(asset);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(ctx)!.aboutUpdateDownloadedTitle),
          content: Text(AppLocalizations.of(ctx)!.aboutUpdateDownloadedBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.close),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _startInstall(apk);
              },
              child: Text(AppLocalizations.of(ctx)!.aboutUpdateInstall),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) await _showError(e.toString());
    } finally {
      if (mounted) setState(() => _downloadInFlight = false);
    }
  }

  Future<void> _startInstall(File apk) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await _updates.install(apk);
    if (!mounted) return;
    switch (result) {
      case UpdateInstallResult.started:
        AppSnack.show(context, l10n.updateInstallerStarted);
      case UpdateInstallResult.permissionRequired:
        final open = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            content: Text(l10n.updateInstallPermission),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.updateOpenPermission),
              ),
            ],
          ),
        );
        if (open == true) await _updates.openInstallPermissionSettings();
      case UpdateInstallResult.failed:
      case UpdateInstallResult.unsupported:
        await _showError('installer unavailable');
    }
  }

  Future<void> _showGithubFallback(String latestName, String releasesUrl) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final name = latestName.trim().isEmpty ? releasesUrl : latestName.trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aboutUpdateFallbackTitle),
        content: Text(l10n.aboutUpdateFallbackBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              await _updates.openUrl(releasesUrl);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l10n.aboutUpdateOpenReleases),
          ),
        ],
      ),
    );
  }

  Future<void> _showError(String error) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.aboutUpdateErrorTitle),
        content: SingleChildScrollView(child: SelectableText(error)),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: error));
              if (ctx.mounted) AppSnack.show(context, l10n.aboutErrorCopied);
            },
            child: Text(l10n.aboutCopyError),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.dialogOk),
          ),
        ],
      ),
    );
  }

  Widget _editionCapsule(BuildContext context, AppLocalizations l10n) {
    final edition = editionFromVersion(
      versionName: _versionName,
      buildNumber: _buildNumber,
    );
    final label = edition == InstalledEdition.preview
        ? l10n.aboutUpdateChannelPreview
        : l10n.aboutUpdateChannelStable;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }

  Widget _heading(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Webdav Media Manager',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          if (_canCheckUpdates) ...[
            Center(child: _editionCapsule(context, l10n)),
            const SizedBox(height: 8),
          ],
          Center(
            child: Text(
              l10n.aboutVersion(_versionLabel),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: AppColors.accent),
            ),
          ),
          if (_canCheckUpdates) ...[
            const SizedBox(height: 8),
            SegmentedButton<UpdateChannel>(
              segments: [
                ButtonSegment(
                  value: UpdateChannel.stable,
                  label: Text(l10n.aboutUpdateChannelStable),
                ),
                ButtonSegment(
                  value: UpdateChannel.preview,
                  label: Text(l10n.aboutUpdateChannelPreview),
                ),
              ],
              selected: {_channel},
              onSelectionChanged: (value) {
                setState(() {
                  _channelTouched = true;
                  _channel = value.first;
                });
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: !_packageReady || _downloadInFlight
                    ? null
                    : _checkForUpdate,
                icon: _downloadInFlight
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_outlined),
                label: Text(l10n.aboutUpdateCheck),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(l10n.aboutDescription),
          const SizedBox(height: 28),
          _heading(context, l10n.aboutCredits),
          const SizedBox(height: 8),
          Text(l10n.aboutImplementation),
          Text(l10n.aboutConcept),
          const SizedBox(height: 8),
          Text(l10n.aboutCreditsHarness),
          Text(l10n.aboutCreditsOpenList),
          Text(l10n.aboutCreditsRclone),
          Text('openlist_crypt：${l10n.aboutCreditsPackages}'),
          const SizedBox(height: 28),
          _heading(context, l10n.aboutLicense),
          const SizedBox(height: 8),
          Text(l10n.aboutLicenseText.replaceAll(r'\n', '\n')),
          const SizedBox(height: 12),
          Text(l10n.aboutCreditsPackages),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: Text(l10n.aboutAllLicenses),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Webdav Media Manager',
                applicationVersion: _versionLabel,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => _updates.openUrl(
                'https://github.com/SenkjM/Webdav_Media_Manager',
              ),
              child: const Text('https://github.com/SenkjM/Webdav_Media_Manager'),
            ),
          ),
        ],
      ),
    );
  }
}
