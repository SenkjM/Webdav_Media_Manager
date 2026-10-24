import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/app_locale.dart';
import '../models/snack_duration.dart';
import '../services/notification_permission_service.dart';
import '../services/rust_core_service.dart';
import '../services/rust_proxy_bridge.dart';
import '../services/rust_queue_bridge.dart';
import '../services/settings_service.dart';
import '../widgets/theme_settings_section.dart';
import '../utils/app_snack.dart';
import 'accounts_screen.dart';
import 'download_settings_screen.dart';
import 'encryption_settings_screen.dart';
import 'file_extensions_screen.dart';
import 'home_shell.dart';
import 'image_settings_screen.dart';
import 'manga_library_settings_screen.dart';
import 'media_library_settings_screen.dart';
import 'openapi_settings_section.dart';
import 'share_settings_screen.dart';
import 'sync_screen.dart';
import 'video_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationPermissionService>().refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<NotificationPermissionService>().refresh();
    }
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (perms.isGranted) {
      AppSnack.show(context, l10n.notificationEnabled);
      return;
    }
    if (perms.isChannelBlocked || perms.isPermanentlyDenied) {
      final opened = await perms.openSystemSettings();
      if (!context.mounted) return;
      AppSnack.show(
        context,
        opened
            ? l10n.notificationOpenSettings
            : l10n.notificationOpenSettingsFailed,
      );
      return;
    }
    final granted = await perms.request();
    if (!context.mounted) return;
    AppSnack.show(
      context,
      granted ? l10n.notificationGranted : l10n.notificationDenied,
    );
  }

  String _notificationSubtitle(NotificationPermissionService perms) {
    final l10n = AppLocalizations.of(context)!;
    if (!perms.loaded) return l10n.notificationChecking;
    if (perms.isGranted) return l10n.notificationStatusAllowed;
    if (perms.isChannelBlocked) return l10n.notificationChannelBlocked;
    if (perms.isPermanentlyDenied) return l10n.notificationStatusDenied;
    if (perms.isChannelMissing) return l10n.notificationChannelMissing;
    return l10n.notificationNotGranted;
  }

  Future<void> _refreshNotificationState(
    BuildContext context,
    NotificationPermissionService perms,
  ) async {
    await perms.refresh();
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final channel = l10n.ntfMediaChannelName;
    final status = perms.channelStatusLabel;
    AppSnack.show(
      context,
      perms.isGranted
          ? l10n.notificationDiagnosticAllowed(channel, status)
          : l10n.notificationDiagnosticDenied(channel, status),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final notif = context.watch<NotificationPermissionService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: Text(l10n.settings),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, l10n.homeAndNavigation),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text(l10n.customHome),
            subtitle: Text(l10n.customHomeSubtitle),
            trailing: DropdownButton<int>(
              borderRadius: BorderRadius.circular(10),
              value: settings.homeTab,
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(l10n.librarySectionFolders),
                ),
                DropdownMenuItem(value: 1, child: Text(l10n.library)),
                DropdownMenuItem(value: 2, child: Text(l10n.playlists)),
                DropdownMenuItem(value: 3, child: Text(l10n.mangaLibrary)),
                DropdownMenuItem(value: 4, child: Text(l10n.networkLibrary)),
                DropdownMenuItem(value: 5, child: Text(l10n.taskQueue)),
                DropdownMenuItem(value: 6, child: Text(l10n.settings)),
              ],
              onChanged: (v) {
                if (v != null) context.read<SettingsService>().setHomeTab(v);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.history),
            title: Text(l10n.rememberNetworkPath),
            subtitle: Text(l10n.rememberNetworkPathSubtitle),
            value: settings.networkRememberLastPath,
            onChanged: (v) =>
                context.read<SettingsService>().setNetworkRememberLastPath(v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.share_outlined),
            title: Text(l10n.shareAction),
            subtitle: Text(l10n.settingsShareSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ShareSettingsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              notif.isGranted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(l10n.mediaNotifications),
            subtitle: Text(_notificationSubtitle(notif)),
            value: notif.isGranted,
            onChanged: (_) => _onNotificationTap(context, notif),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq),
            title: Text(l10n.ntfMediaChannelName),
            subtitle: Text(notif.channelStatusLabel),
            trailing: TextButton(
              onPressed: () => _refreshNotificationState(context, notif),
              child: Text(l10n.refresh),
            ),
          ),
          if (!notif.isGranted)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _onNotificationTap(context, notif),
                icon: const Icon(Icons.notification_add_outlined),
                label: Text(
                  (notif.isPermanentlyDenied || notif.isChannelBlocked)
                      ? l10n.openSystemSettings
                      : l10n.requestNotificationPermission,
                ),
              ),
            ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.mediaLibrarySection),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_music_outlined),
            title: Text(l10n.mediaLibrarySettings),
            subtitle: Text(l10n.mediaLibrarySettingsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MediaLibrarySettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.mangaLibrarySettingsSection),
            subtitle: Text(l10n.mangaLibrarySettingsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MangaLibrarySettingsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.networkLibrary),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: Text(l10n.accountsTitle),
            subtitle: Text(l10n.accountsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.download),
            subtitle: Text(l10n.downloadQueueSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DownloadSettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.encryptionSettings),
            subtitle: Text(l10n.encryptionSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EncryptionSettingsScreen(),
                ),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_library_outlined),
            title: Text(l10n.videoSettings),
            subtitle: Text(l10n.videoSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VideoSettingsScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image_outlined),
            title: Text(l10n.imageViewer),
            subtitle: Text(l10n.imageViewerSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImageSettingsScreen()),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.extension_outlined),
            title: Text(l10n.fileTypesManage),
            subtitle: Text(l10n.fileTypesManageSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FileExtensionsScreen()),
              );
            },
          ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.settingsMisc),
          const SizedBox(height: 8),
          ThemeSettingsSection(
            mode: settings.appThemeMode,
            onModeChanged: (value) {
              context.read<SettingsService>().setAppThemeMode(value);
            },
            seed: settings.themeSeed,
            onSeedChanged: (color) {
              context.read<SettingsService>().setThemeSeed(color);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(l10n.language),
            subtitle: Text(l10n.languageSettingSubtitle),
            trailing: DropdownButton<AppLocalePreference>(
              borderRadius: BorderRadius.circular(10),
              value: settings.appLocale,
              items: [
                DropdownMenuItem(
                  value: AppLocalePreference.system,
                  child: Text(l10n.languageSystem),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.zhCN,
                  child: Text(AppLocalePreference.zhCN.nativeName!),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.zhTW,
                  child: Text(AppLocalePreference.zhTW.nativeName!),
                ),
                DropdownMenuItem(
                  value: AppLocalePreference.en,
                  child: Text(AppLocalePreference.en.nativeName!),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  context.read<SettingsService>().setAppLocale(value);
                }
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.hintDuration),
            subtitle: Text(settings.snackMode.label(l10n)),
            trailing: DropdownButton<SnackDuration>(
              borderRadius: BorderRadius.circular(10),
              value: settings.snackMode,
              items: [
                for (final m in SnackDuration.values)
                  DropdownMenuItem(value: m, child: Text(m.label(l10n))),
              ],
              onChanged: (v) {
                if (v != null) settings.setSnackMode(v);
              },
            ),
          ),
          const Divider(height: 40),
          _sectionTitle(context, l10n.syncAndBackup),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: Text(l10n.syncSettings),
            subtitle: Text(
              '${l10n.settingsSyncSharedPath}\n'
              '${settings.syncRemoteRoot}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SyncScreen()));
            },
          ),

          Text(
            l10n.settingsPlaybackFooter,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // ── Developer: OpenAPI + Rust Queue + Rust Proxy (debug only) ──────
          if (kDebugMode) ...[
            const Divider(height: 40),
            _sectionTitle(context, 'Developer / OpenAPI'),
            const SizedBox(height: 8),
            const OpenApiSettingsSection(),
            const Divider(height: 24),
            _sectionTitle(context, 'Developer / Rust Queue'),
            const SizedBox(height: 8),
            const _RustQueueSettingsSection(),
            const Divider(height: 24),
            _sectionTitle(context, 'Developer / Rust Proxy'),
            const SizedBox(height: 8),
            const _RustProxySettingsSection(),
          ],
        ],
      ),
    );
  }
}

// ── Rust Queue settings section (debug only) ─────────────────────────────────

/// Shows Rust queue status and a diagnostic poll button.
///
/// The [kRustQueueEnabled] const is intentionally left `false` — it gates the
/// actual download routing.  This section only shows poll output so a developer
/// can verify queue serialisation without rerouting live downloads.
///
/// ## One happy-path device smoke
/// 1. Build with `cargo-ndk` + `flutter run`.
/// 2. Enqueue one download from the network library.
/// 3. Open Settings → Developer / Rust Queue → tap "Poll status".
/// 4. Confirm the task appears with status "Pending" (Dart side handles it).
/// 5. To test Rust routing: change `kRustQueueEnabled = true` in
///    `rust_queue_bridge.dart`, rebuild, repeat step 2-3 and confirm
///    `[RustQueueBridge] enqueue ok` in logcat.
class _RustQueueSettingsSection extends StatefulWidget {
  const _RustQueueSettingsSection();

  @override
  State<_RustQueueSettingsSection> createState() =>
      _RustQueueSettingsSectionState();
}

class _RustQueueSettingsSectionState
    extends State<_RustQueueSettingsSection> {
  String _statusJson = '(not polled)';
  int _pendingCount = 0;

  void _poll() {
    final json = RustQueueBridge.pollStatus();
    final count = RustCoreService.queuePendingCount();
    setState(() {
      _statusJson = json.isEmpty ? '[]' : json;
      _pendingCount = count;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.queue_outlined),
          title: const Text('Rust queue enabled'),
          subtitle: Text(
            kRustQueueEnabled
                ? 'ON — downloads routed through SerialPump'
                : 'OFF (default) — Dart TaskQueueService is active.\n'
                  'Set kRustQueueEnabled=true in rust_queue_bridge.dart '
                  'and rebuild to enable Rust routing.',
          ),
          trailing: Switch(
            value: kRustQueueEnabled,
            // kRustQueueEnabled is a compile-time const; rebuild required.
            // Switch is display-only; tapping it shows a hint.
            onChanged: (_) => AppSnack.show(
              context,
              'Change kRustQueueEnabled in rust_queue_bridge.dart and rebuild.',
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.refresh_outlined),
          title: const Text('Poll Rust queue status'),
          subtitle: Text('Pending tasks: $_pendingCount'),
          trailing: TextButton(
            onPressed: _poll,
            child: const Text('Poll'),
          ),
        ),
        if (_statusJson != '(not polled)')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SelectableText(
              _statusJson,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Serial invariant: SerialPump enforces concurrency = 1. '
            'Never introduce a concurrency knob on either side.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

// ── Rust Proxy settings section (debug only) ─────────────────────────────────

/// Thin developer note for the Rust local HTTP proxy.
///
/// [kRustProxyEnabled] is `true` (Round 11 cutover complete). This section
/// surfaces the Rust proxy state (port, start/stop/register) for developer
/// validation.
///
/// ## Round 12.1 status
/// - DLNA cast uses `wdmm_proxy_register_hls` via [RustDlnaCastService].
/// - `LocalStreamBridge` (Dart HTTP proxy for MustProxy/crypt) **deleted** in R12.1.
///   MustProxy playback broken until `wdmm_proxy_register_stream` lands in Core.
///   TODO(proxy-cutover): wire wdmm_proxy_register_stream then restore MustProxy.
class _RustProxySettingsSection extends StatefulWidget {
  const _RustProxySettingsSection();

  @override
  State<_RustProxySettingsSection> createState() =>
      _RustProxySettingsSectionState();
}

class _RustProxySettingsSectionState extends State<_RustProxySettingsSection> {
  int _port = -1;

  void _refresh() {
    setState(() => _port = RustProxyBridge.port());
  }

  void _start() {
    final p = RustProxyBridge.start();
    setState(() => _port = p ?? -1);
    if (p == null) {
      AppSnack.show(context, 'Rust proxy start failed (see logs).');
    }
  }

  void _stop() {
    RustProxyBridge.stop();
    setState(() => _port = -1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cast_connected_outlined),
          title: const Text('Rust proxy enabled'),
          subtitle: Text(
            kRustProxyEnabled
                ? 'ON — local files served via wdmm-proxy singleton\n'
                  'DLNA cast uses wdmm_proxy_register_hls (R12). '
                  'LocalStreamBridge deleted (R12.1); MustProxy awaits wdmm_proxy_register_stream.'
                : 'OFF — set kRustProxyEnabled=true in rust_proxy_bridge.dart '
                  'and rebuild to enable the Rust proxy.',
          ),
          trailing: Switch(
            value: kRustProxyEnabled,
            // Compile-time const; display-only — tapping shows a hint.
            onChanged: (_) => AppSnack.show(
              context,
              'Change kRustProxyEnabled in rust_proxy_bridge.dart and rebuild.',
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.settings_ethernet),
          title: const Text('Rust proxy port'),
          subtitle: Text(_port >= 0 ? '$_port' : '(not running)'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: kRustProxyEnabled ? _start : null, child: const Text('Start')),
              TextButton(onPressed: kRustProxyEnabled ? _stop : null, child: const Text('Stop')),
              TextButton(onPressed: _refresh, child: const Text('Poll')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Round 12.1: LocalStreamBridge (Dart MustProxy HTTP bridge) deleted. '
            'MustProxy/crypt playback broken until wdmm_proxy_register_stream lands. '
            'The Rust proxy is a process-global singleton — never create a second instance.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
