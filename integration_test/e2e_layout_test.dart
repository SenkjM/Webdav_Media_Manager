import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webdav_media_manager/screens/accounts_screen.dart';
import 'package:webdav_media_manager/screens/download_settings_screen.dart';
import 'package:webdav_media_manager/screens/encryption_settings_screen.dart';
import 'package:webdav_media_manager/screens/file_extensions_screen.dart';
import 'package:webdav_media_manager/screens/image_settings_screen.dart';
import 'package:webdav_media_manager/screens/manga_library_settings_screen.dart';
import 'package:webdav_media_manager/screens/media_library_settings_screen.dart';
import 'package:webdav_media_manager/screens/openapi_settings_screen.dart';
import 'package:webdav_media_manager/screens/settings_screen.dart';
import 'package:webdav_media_manager/screens/share_settings_screen.dart';
import 'package:webdav_media_manager/screens/sync_screen.dart';
import 'package:webdav_media_manager/screens/transcode_presets_screen.dart';
import 'package:webdav_media_manager/screens/video_settings_screen.dart';

import 'e2e_support.dart';

/// UI module: push every settings screen and fail on layout overflows.
///
/// Flutter reports `RenderFlex overflowed by N pixels` as a framework error and
/// the message names the offending widget's file and line, so this sweep turns
/// "settings look broken on my phone" into exact locations instead of guesses.
///
/// The sweep deliberately does **not** navigate the shell: the app may restore a
/// playback route on launch, and popping through it stalled the test runner.
/// Pushing each screen onto the root navigator tests the same layouts, in a
/// fixed order, and never depends on translated labels or scroll positions.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ui: settings screens do not overflow', (tester) async {
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.toLowerCase().contains('overflow')) {
        final where = details.context?.toString() ?? '';
        final info = details.informationCollector
                ?.call()
                .map((node) => node.toString())
                .join(' | ') ??
            '';
        overflows.add('$text\n$where\n$info');
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    debugPrint('[E2E] ui: booting');
    await bootApp(tester);
    debugPrint('[E2E] ui: booted');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    var seen = 0;

    Future<void> visit(String name, Widget screen) async {
      debugPrint('[E2E] ui: push $name');
      navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
      await pumpFrames(tester, label: name);
      for (var i = seen; i < overflows.length; i++) {
        debugPrint('[E2E] ui: overflow on $name\n${overflows[i]}');
      }
      seen = overflows.length;
      if (navigator.canPop()) {
        navigator.pop();
        await pumpFrames(tester, frames: 8, label: '$name pop');
      }
      debugPrint('[E2E] ui: done $name (${overflows.length} report(s))');
    }

    await visit('settings root', const SettingsScreen());
    await visit('accounts', const AccountsScreen());
    await visit('download', const DownloadSettingsScreen());
    await visit('encryption', const EncryptionSettingsScreen());
    await visit('video', const VideoSettingsScreen());
    await visit('image', const ImageSettingsScreen());
    await visit('file types', const FileExtensionsScreen());
    await visit('share', const ShareSettingsScreen());
    await visit('media library', const MediaLibrarySettingsScreen());
    await visit('manga library', const MangaLibrarySettingsScreen());
    await visit('sync', const SyncScreen());
    await visit('transcode presets', const TranscodePresetsScreen());
    await visit('openapi', const OpenApiSettingsScreen());

    debugPrint('[E2E] ui: ${overflows.length} overflow report(s)');
    expect(overflows, isEmpty,
        reason: 'layouts overflow:\n${overflows.join('\n---\n')}');
  });
}
