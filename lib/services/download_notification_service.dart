import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/download_task.dart';

/// Android notification channels for the download queue.
///
/// Two channels on purpose:
/// * **进度** — low importance, silent, rewritten several times a second while
///   files transfer;
/// * **完成** — default importance, silent, posted once when the queue drains so
///   the result is still readable after the progress notifications are gone.
///
/// Both are separate from the media channel, which is owned by `audio_service`.
const String kDownloadChannelId = 'com.webdav.webdav_music_player.downloads.v1';
const String kDownloadChannelName = '下载进度';
const String kDownloadChannelDescription = '下载队列进行中的进度';

const String kDownloadDoneChannelId =
    'com.webdav.webdav_music_player.downloads.done.v1';
const String kDownloadDoneChannelName = '下载完成';
const String kDownloadDoneChannelDescription = '全部下载完成后的结果汇总';

const AndroidNotificationChannel kDownloadChannel = AndroidNotificationChannel(
  kDownloadChannelId,
  kDownloadChannelName,
  description: kDownloadChannelDescription,
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
  showBadge: false,
);

const AndroidNotificationChannel kDownloadDoneChannel =
    AndroidNotificationChannel(
      kDownloadDoneChannelId,
      kDownloadDoneChannelName,
      description: kDownloadDoneChannelDescription,
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

/// System notifications for the download queue.
///
/// A single Android notification can only carry **one** progress bar, so the two
/// levels the user asked for are two notifications:
///
/// * [currentId] — the file being transferred right now (its own percentage);
/// * [queueId] — the whole batch (finished files + the current one's fraction).
///
/// Both are cancelled the moment the queue drains and a separate
/// [summaryId] 「全部下载完成」 notification is posted, so the counts never leak
/// into the next batch.
class DownloadNotificationService {
  DownloadNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The file currently transferring. Rewritten on every progress frame.
  static const int currentId = 2001;

  /// The whole batch.
  static const int queueId = 2002;

  /// 「全部下载完成」 — posted after the queue drains.
  static const int summaryId = 2003;

  /// Throttle: progress updates at most this often.
  static const Duration progressInterval = Duration(milliseconds: 700);

  bool _initialized = false;

  /// Whether notifications are currently allowed at all.
  bool enabled = true;

  /// Last time a notification was actually posted (throttling).
  DateTime? _lastPost;
  int? _lastCurrentPercent;
  int? _lastQueuePercent;
  int _lastDone = -1;
  int _lastTotal = -1;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> ensureChannel() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await _ensureInitialized();
    try {
      await _android?.createNotificationChannel(kDownloadChannel);
      await _android?.createNotificationChannel(kDownloadDoneChannel);
      return true;
    } catch (e) {
      debugPrint('DownloadNotification: ensureChannel failed: $e');
      return false;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (e) {
      // Platform channel unavailable (tests / non-Android host).
      debugPrint('DownloadNotification: initialize failed: $e');
    }
    _initialized = true;
  }

  static NotificationDetails _progressDetails({required int percent}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          kDownloadChannelId,
          kDownloadChannelName,
          channelDescription: kDownloadChannelDescription,
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          // `showProgress` alone renders an empty determinate bar (the "grey
          // line" the user saw) — `progress` must be set as well.
          showProgress: true,
          maxProgress: 100,
          progress: percent.clamp(0, 100),
          ongoing: false,
          autoCancel: true,
          showWhen: false,
          icon: 'drawable/ic_stat_download',
          playSound: false,
          enableVibration: false,
        ),
      );

  static NotificationDetails _summaryDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      kDownloadDoneChannelId,
      kDownloadDoneChannelName,
      channelDescription: kDownloadDoneChannelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
      ongoing: false,
      autoCancel: true,
      showWhen: true,
      icon: 'drawable/ic_stat_download',
      playSound: false,
      enableVibration: false,
    ),
  );

  /// Two-level progress: [index]/[total] is the position of the running file,
  /// [fileProgress] its own 0..1 fraction and [done] how many files already
  /// finished in **this** batch.
  ///
  /// Throttled by [progressInterval] and by integer percent so a fast download
  /// does not post hundreds of updates.
  Future<void> showProgress({
    required int index,
    required int total,
    required int done,
    required String? currentName,
    required double fileProgress,
    bool force = false,
  }) async {
    if (!enabled || kIsWeb || !Platform.isAndroid) return;
    final currentPercent = (fileProgress.clamp(0.0, 1.0) * 100).round();
    final queueFraction = total == 0
        ? 0.0
        : (done + fileProgress.clamp(0.0, 1.0)) / total;
    final queuePercent = (queueFraction.clamp(0.0, 1.0) * 100).round();
    final now = DateTime.now();
    if (!force) {
      final unchanged =
          currentPercent == _lastCurrentPercent &&
          queuePercent == _lastQueuePercent &&
          done == _lastDone &&
          total == _lastTotal;
      if (unchanged) return;
      final last = _lastPost;
      if (last != null && now.difference(last) < progressInterval) return;
    }
    _lastPost = now;
    _lastCurrentPercent = currentPercent;
    _lastQueuePercent = queuePercent;
    _lastDone = done;
    _lastTotal = total;
    final safeTotal = total == 0 ? 1 : total;
    final name = currentName ?? '准备中';
    await _ensureInitialized();
    try {
      // Level 1 — the file being transferred.
      await _plugin.show(
        id: currentId,
        title: '正在下载（第 $index / $safeTotal 个）',
        body: '$name\n$currentPercent%',
        notificationDetails: _progressDetails(percent: currentPercent),
      );
      // Level 2 — the whole batch.
      await _plugin.show(
        id: queueId,
        title: '下载队列（$safeTotal 个任务）',
        body: '总进度 $queuePercent% · 已完成 $done / $safeTotal',
        notificationDetails: _progressDetails(percent: queuePercent),
      );
    } catch (e) {
      // Notification failures must never break the download itself.
      debugPrint('DownloadNotification: showProgress failed: $e');
    }
  }

  /// Drop both progress notifications (the queue drained or was cleared).
  Future<void> clearProgress() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _ensureInitialized();
    try {
      await _plugin.cancel(id: currentId);
      await _plugin.cancel(id: queueId);
    } catch (e) {
      debugPrint('DownloadNotification: clearProgress failed: $e');
    }
  }

  /// 「全部下载完成（成功：x 个 失败：y 个）」 — a *new* notification, not a mutation
  /// of the progress one, and it stays until dismissed or replaced by a later
  /// batch's summary.
  Future<void> showSummary({
    required int completed,
    required int failed,
    required int cancelled,
  }) async {
    if (!enabled || kIsWeb || !Platform.isAndroid) return;
    if (completed == 0 && failed == 0 && cancelled == 0) return;
    final allOk = failed == 0 && cancelled == 0;
    final parts = <String>[
      '成功：$completed 个',
      if (failed > 0) '失败：$failed 个',
      if (cancelled > 0) '取消：$cancelled 个',
    ];
    await _ensureInitialized();
    try {
      await _plugin.show(
        id: summaryId,
        title: allOk ? '全部下载完成' : '下载结束（有失败）',
        body: parts.join('　'),
        notificationDetails: _summaryDetails(),
      );
    } catch (e) {
      debugPrint('DownloadNotification: showSummary failed: $e');
      return;
    }
  }

  /// Progress line for a single task (used when only one is running).
  String describe(DownloadTask task) =>
      '${task.fileName} · ${(task.progress * 100).toStringAsFixed(0)}%';

  /// Cancel everything this service ever posted (used when the feature is turned
  /// off or the queue is cleared).
  Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _ensureInitialized();
    try {
      await _plugin.cancel(id: currentId);
      await _plugin.cancel(id: queueId);
      await _plugin.cancel(id: summaryId);
    } catch (_) {}
    _lastCurrentPercent = null;
    _lastQueuePercent = null;
    _lastDone = -1;
    _lastTotal = -1;
  }
}
