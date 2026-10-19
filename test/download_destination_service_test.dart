// SPDX-FileCopyrightText: 2025 Webdav Media Manager contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_media_manager/services/download_destination_service.dart';
import 'package:webdav_media_manager/services/platform_export_service.dart';
import 'package:webdav_media_manager/services/settings_service.dart';

class FakeExport extends PlatformExportService {
  FakeExport();

  ExportResult? treeResult;
  ExportResult? downloadsResult;
  DownloadsNomediaResult treeNomediaResult =
      const DownloadsNomediaResult(alreadyMatched: true);
  DownloadsNomediaResult downloadsNomediaResult =
      const DownloadsNomediaResult(alreadyMatched: true);

  int saveToTreeCalls = 0;
  int saveToDownloadsCalls = 0;
  int releaseCalls = 0;
  int setTreeNomediaCalls = 0;
  int setDownloadsNomediaCalls = 0;
  String? lastTreeUri;
  String? lastDownloadsSubdir;

  @override
  Future<ExportResult> saveToTree({
    required String treeUri,
    required String sourcePath,
    required String fileName,
    String? mimeType,
  }) async {
    saveToTreeCalls++;
    lastTreeUri = treeUri;
    return treeResult ??
        ExportResult.failure('unset', errorKind: 'other');
  }

  @override
  Future<ExportResult> saveToDownloads({
    required String sourcePath,
    required String fileName,
    String? mimeType,
    String subdir = 'WebdavMediaManager',
  }) async {
    saveToDownloadsCalls++;
    lastDownloadsSubdir = subdir;
    return downloadsResult ??
        const ExportResult(
          ok: true,
          fileName: 'f.bin',
          location: 'downloads',
          path: '/dl/f.bin',
          gallery: false,
        );
  }

  @override
  Future<bool> releaseDownloadTree(String uri) async {
    releaseCalls++;
    return true;
  }

  @override
  Future<bool> checkDownloadTree(String uri) async => true;

  @override
  Future<DownloadsNomediaResult> setTreeNomedia({
    required String treeUri,
    required bool enabled,
  }) async {
    setTreeNomediaCalls++;
    lastTreeUri = treeUri;
    return treeNomediaResult;
  }

  @override
  Future<DownloadsNomediaResult> setDownloadsNomedia({
    required bool enabled,
  }) async {
    setDownloadsNomediaCalls++;
    return downloadsNomediaResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;
  late FakeExport export;
  late DownloadDestinationService destination;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs: prefs);
    await settings.init();
    export = FakeExport();
    destination = DownloadDestinationService(
      settings: settings,
      export: export,
    );
  });

  Future<void> enableCustom() async {
    await settings.setCustomDownloadDir(
      uri: 'content://tree/test',
      displayName: 'TestDir',
    );
  }

  test('safInvalid falls back once; second fallback is no-op; io does not fall back',
      () async {
    await enableCustom();
    export.treeResult =
        ExportResult.failure('gone', errorKind: 'safInvalid');

    final r1 = await destination.save(
      sourcePath: '/tmp/a',
      fileName: 'a.bin',
      retryOnFallback: false,
    );
    expect(r1.ok, isFalse);
    expect(r1.safInvalid, isTrue);
    expect(r1.error, 'err.customDirInvalid');
    expect(settings.customDownloadDirActive, isFalse);
    expect(export.releaseCalls, 1);
    expect(export.saveToDownloadsCalls, 0);

    final again = await destination.fallbackToDefault();
    expect(again, isFalse);
    expect(export.releaseCalls, 1);

    await enableCustom();
    export.treeResult = ExportResult.failure('disk full', errorKind: 'io');
    final rIo = await destination.save(
      sourcePath: '/tmp/a',
      fileName: 'a.bin',
      retryOnFallback: false,
    );
    expect(rIo.ok, isFalse);
    expect(rIo.errorKind, 'io');
    expect(settings.customDownloadDirActive, isTrue);
    expect(export.releaseCalls, 1);
  });

  test('retryOnFallback true writes MediaStore and sets fellBack', () async {
    await enableCustom();
    export.treeResult =
        ExportResult.failure('gone', errorKind: 'safInvalid');
    export.downloadsResult = const ExportResult(
      ok: true,
      fileName: 'a.bin',
      location: 'downloads',
      path: '/dl/a.bin',
      gallery: false,
    );

    final r = await destination.save(
      sourcePath: '/tmp/a',
      fileName: 'a.bin',
      mediaStoreSubdir: 'WebdavMediaManager/recovery',
      retryOnFallback: true,
    );
    expect(r.ok, isTrue);
    expect(r.fellBack, isTrue);
    expect(export.saveToDownloadsCalls, 1);
    expect(export.lastDownloadsSubdir, 'WebdavMediaManager/recovery');
    expect(settings.customDownloadDirActive, isFalse);
  });

  test('alignNomedia picks SAF vs MediaStore target', () async {
    await destination.alignNomedia();
    expect(export.setDownloadsNomediaCalls, 1);
    expect(export.setTreeNomediaCalls, 0);

    await enableCustom();
    await destination.alignNomedia();
    expect(export.setTreeNomediaCalls, 1);
  });
}
