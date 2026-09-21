import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/media_notification_channel.dart';
import 'package:webdav_media_manager/services/music_audio_handler.dart'
    as handler;
import 'package:webdav_media_manager/services/notification_permission_service.dart';

void main() {
  test('media channel id stays the v4 ColorOS-fresh channel', () {
    expect(
      kMediaNotificationChannelId,
      'com.senkjm.media_manager.audio.v4',
    );
    // Still re-exported from music_audio_handler.dart for existing importers.
    expect(handler.kMediaNotificationChannelId, kMediaNotificationChannelId);
  });

  test('channel definition mirrors audio_service native createChannel()', () {
    final channel = kMediaNotificationChannel;
    expect(channel.id, kMediaNotificationChannelId);
    expect(channel.name, kMediaNotificationChannelName);
    expect(channel.description, kMediaNotificationChannelDescription);
    // Vendored audio_service (AudioService.java createChannel) uses
    // IMPORTANCE_DEFAULT, setSound(null, null), enableVibration(false),
    // setShowBadge(androidShowNotificationBadge = false).
    expect(channel.importance, Importance.defaultImportance);
    expect(channel.playSound, isFalse);
    expect(channel.enableVibration, isFalse);
    expect(channel.showBadge, isFalse);
    expect(kMediaNotificationIcon, 'drawable/ic_stat_music');
  });

  test('service creates the channel itself and is inert off Android', () async {
    final service = NotificationPermissionService();
    // Host test runner is not Android: no channels, no permission dialog.
    expect(service.supportsChannels, isFalse);
    expect(service.requiresRuntimePermission, isFalse);
    expect(await service.ensureChannel(), isFalse);

    await service.refresh();
    expect(service.loaded, isTrue);
    expect(service.isGranted, isTrue);
    expect(service.isChannelBlocked, isFalse);
    expect(service.isChannelMissing, isFalse);
    expect(service.channelStatusLabel, '当前平台无通知通道');
    expect(await service.openSystemSettings(), isFalse);
  });
}
