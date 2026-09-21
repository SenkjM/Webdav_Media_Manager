import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/download_task.dart';

/// Android notification channels for the download queue.
///
/// Two channels on purpose:
/// * **进度** — silent, rewritten several times a second while files transfer;
/// * **完成** — silent, posted once when the queue drains so the result is still
///   readable after the progress notification is gone.
///
/// Both are separate from the media channel, which is owned by `audio_service`.
///
/// The progress channel is `.v2`: the `.v1` channel was created with
/// `Importance.low`, and ColorOS folded it into 不重要通知 (the system reported
/// `mUnimportant=true`), so progress was invisible even though it was posted.
/// Android never raises the importance of an existing channel, hence the new id
/// — and [DownloadNotificationService.ensureChannel] deletes the stale one.
const String kDownloadChannelId =
    'com.webdav.webdav_music_player.downloads.v2';
const String kDownloadChannelName = '下载进度';
const String kDownloadChannelDescription = '下载队列进行中的进度';

/// Superseded by [kDownloadChannelId]; removed on startup.
const String kLegacyDownloadChannelId =
    'com.webdav.webdav_music_player.downloads.v1';

const String kDownloadDoneChannelId =
    'com.webdav.webdav_music_player.downloads.done.v1';
const String kDownloadDoneChannelName = '下载完成';
const String kDownloadDoneChannelDescription = '全部下载完成后的结果汇总';

const AndroidNotificationChannel kDownloadChannel = AndroidNotificationChannel(
  kDownloadChannelId,
  kDownloadChannelName,
  description: kDownloadChannelDescription,
  // Default (not low) importance: ColorOS hides low-importance notifications in
  // 不重要通知, which made them look like they were never posted. Silence still
  // comes from `playSound`/`enableVibration`/`silent` on the notification.
  importance: Importance.defaultImportance,
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
/// Two notifications at most, on two channels:
///
/// * [currentId] — the file being transferred, with its own percentage **and**
///   the batch position/counts in one line;
/// * [summaryId] — 「全部下载完成」, posted once when the queue drains.
///
/// There is deliberately no separate queue-level notification: it carried no
/// information the current-file line does not, and the two of them stole each
/// other's autogroup slot in the shade.
class DownloadNotificationService {
  DownloadNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The file currently transferring. Rewritten on every progress frame.
  static const int currentId = 2001;

  /// Retired queue-level notification; cancelled so no stale bar lingers.
  static const int legacyQueueId = 2002;

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
      // Drop the old low-importance channel so it stops showing up (and stops
      // swallowing progress) in system settings.
      try {
        await _android?.deleteNotificationChannel(
          channelId: kLegacyDownloadChannelId,
        );
      } catch (e) {
        debugPrint('DownloadNotification: deleteLegacyChannel failed: $e');
      }
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
          // Silent by construction: progress repaints constantly and must never
          // buzz or pop a heads-up.
          silent: true,
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

  /// One progress notification for the whole queue: the running file's own
  /// percentage on the bar, plus its position and the batch counts in the body.
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
    final counts = queuePercent == currentPercent
        ? '已完成 $done / $safeTotal'
        : '总进度 $queuePercent% · 已完成 $done / $safeTotal';
    await _ensureInitialized();
    try {
      await _plugin.show(
        id: currentId,
        title: '正在下载（第 $index / $safeTotal 个）',
        body: '$name\n$currentPercent% · $counts',
        notificationDetails: _progressDetails(percent: currentPercent),
      );
    } catch (e) {
      // Notification failures must never break the download itself.
      debugPrint('DownloadNotification: showProgress failed: $e');
    }
  }

  /// Drop the progress notification (the queue drained or was cleared) together
  /// with the retired queue-level one, so nothing stale survives an upgrade.
  Future<void> clearProgress() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _ensureInitialized();
    try {
      await _plugin.cancel(id: currentId);
      await _plugin.cancel(id: legacyQueueId);
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
      await _plugin.cancel(id: legacyQueueId);
      await _plugin.cancel(id: summaryId);
    } catch (_) {}
    _lastCurrentPercent = null;
    _lastQueuePercent = null;
    _lastDone = -1;
    _lastTotal = -1;
  }
}
