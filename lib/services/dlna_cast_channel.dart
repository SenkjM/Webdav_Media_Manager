import 'package:flutter/services.dart';

/// Thin wrapper around the Android `DlnaCastService` platform channel.
///
/// The service acquires a Wi-Fi MulticastLock so the kernel delivers SSDP
/// multicast packets to Dart's [RawDatagramSocket]. Call [start] before
/// opening the discovery socket and [stop] when discovery + cast are done.
///
/// On non-Android platforms all calls are no-ops (returns true silently).
class DlnaCastChannel {
  DlnaCastChannel._();

  static const _channel =
      MethodChannel('com.senkjm.media_manager/dlna_cast');

  /// Starts the foreground service and acquires the MulticastLock.
  /// Returns `true` on success. Idempotent if already running.
  static Future<bool> start() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('start');
      return (res?['ok'] as bool?) ?? false;
    } on MissingPluginException {
      // Non-Android (desktop, iOS): no-op.
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stops the foreground service and releases the MulticastLock.
  static Future<bool> stop() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('stop');
      return (res?['ok'] as bool?) ?? false;
    } on MissingPluginException {
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Returns `true` if the service is currently running.
  static Future<bool> isRunning() async {
    try {
      final res =
          await _channel.invokeMapMethod<String, dynamic>('isRunning');
      return (res?['running'] as bool?) ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      return false;
    }
  }
}
