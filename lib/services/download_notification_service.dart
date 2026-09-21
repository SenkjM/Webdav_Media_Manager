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
const String kDownloadChannelId = 'com.senkjm.media_manager.downloads.v1';
const String kDownloadChannelName = '下载进度';
const String kDownloadChannelDescription = '下载队列进行中的进度';

const String kDownloadDoneChannelId =
    'com.senkjm.media_manager.downloads.done.v1';
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

  /// One-off diagnostic: posts a progress + a summary notification and reports
  /// what the system said, so 「看不到通知」 can be pinned to a cause without a
  /// real download. Returns null on success, else a short reason.
  Future<String?> selfTest() async {
    if (kIsWeb || !Platform.isAndroid) return '仅 Android 支持';
    final wasEnabled = enabled;
    enabled = true;
    try {
      final allowed = await _android?.areNotificationsEnabled();
      if (allowed == false) return '系统已关闭本应用的通知';
      await ensureChannel();
      await _ensureInitialized();
      await _plugin.show(
        id: currentId,
        title: '正在下载（第 1 / 1 个）',
        body: '测试通知 · 50% · 已完成 0 / 1',
        notificationDetails: _progressDetails(percent: 50),
      );
      await _plugin.show(
        id: summaryId,
        title: '全部下载完成',
        body: '成功：1 个（测试）',
        notificationDetails: _summaryDetails(),
      );
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      enabled = wasEnabled;
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
