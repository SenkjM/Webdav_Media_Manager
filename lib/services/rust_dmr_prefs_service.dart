import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Model
// ──────────────────────────────────────────────────────────────────────────────

/// Per-device DMR (DLNA MediaRenderer) compatibility preferences.
///
/// Keyed by SSDP USN. Persisted in SharedPreferences as a JSON map until the
/// Rust-side `wdmm_dmr_prefs_*` FFI is available
/// (TODO: migrate to Rust FFI in Round 12 once the FFI exports land).
class DmrDevicePrefs {
  const DmrDevicePrefs({
    this.displayName,
    this.remuxContainer = false,
    this.transcodeVideo = false,
    this.transcodeAudio = false,
  });

  /// User-set friendly display name override (null = use renderer's own name).
  final String? displayName;

  /// Container remux: MKV/AVI/… → MP4 without re-encoding (low CPU).
  final bool remuxContainer;

  /// Video transcode to H.264 (high CPU).
  final bool transcodeVideo;

  /// Audio transcode to AAC (medium CPU).
  final bool transcodeAudio;

  bool get anyEnabled => remuxContainer || transcodeVideo || transcodeAudio;

  DmrDevicePrefs copyWith({
    String? displayName,
    bool clearDisplayName = false,
    bool? remuxContainer,
    bool? transcodeVideo,
    bool? transcodeAudio,
  }) => DmrDevicePrefs(
    displayName: clearDisplayName ? null : (displayName ?? this.displayName),
    remuxContainer: remuxContainer ?? this.remuxContainer,
    transcodeVideo: transcodeVideo ?? this.transcodeVideo,
    transcodeAudio: transcodeAudio ?? this.transcodeAudio,
  );

  factory DmrDevicePrefs.fromJson(Map<String, dynamic> j) => DmrDevicePrefs(
    displayName: j['display_name'] as String?,
    remuxContainer: (j['remux_container'] as bool?) ?? false,
    transcodeVideo: (j['transcode_video'] as bool?) ?? false,
    transcodeAudio: (j['transcode_audio'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    if (displayName != null) 'display_name': displayName,
    'remux_container': remuxContainer,
    'transcode_video': transcodeVideo,
    'transcode_audio': transcodeAudio,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// Service
// ──────────────────────────────────────────────────────────────────────────────

/// Persists per-device DMR compatibility settings keyed by SSDP USN.
///
/// ### Migration note (temporary Dart store)
/// `wdmm_dmr_prefs_*` FFI exports are NOT present in the current wdmm-core
/// submodule (SHA 4a37aa4, feat/proxy-hls-ffmpeg). This service uses
/// SharedPreferences as a migration-keyed temporary store. Once the Rust FFI
/// lands, replace this class body with thin FFI wrappers and migrate the
/// SharedPrefs data into the Rust DB on first open.
///
/// Keys in SharedPreferences: `dmr_prefs.<USN>`
/// Backup: `exportForBackup()` / `importFromBackup()` for inclusion in the
/// WmpContainer backup archive.
class RustDmrPrefsService extends ChangeNotifier {
  static const _kPrefix = 'dmr_prefs.';

  SharedPreferences? _prefs;

  // In-memory cache: USN → DmrDevicePrefs
  final Map<String, DmrDevicePrefs> _cache = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadAll();
  }

  void _loadAll() {
    final prefs = _prefs;
    if (prefs == null) return;
    _cache.clear();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_kPrefix)) continue;
      final usn = key.substring(_kPrefix.length);
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _cache[usn] = DmrDevicePrefs.fromJson(j);
      } catch (e) {
        debugPrint('[DmrPrefs] parse error for $usn: $e');
      }
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns all stored USNs.
  List<String> get usns => List.unmodifiable(_cache.keys.toList());

  /// Returns all stored [DmrDevicePrefs], keyed by USN.
  Map<String, DmrDevicePrefs> get all => Map.unmodifiable(_cache);

  /// Returns preferences for [usn], or null if not stored.
  DmrDevicePrefs? get(String usn) => _cache[usn];

  /// Upserts preferences for [usn]. Persists immediately to SharedPreferences.
  Future<void> upsert(String usn, DmrDevicePrefs prefs) async {
    _cache[usn] = prefs;
    await _prefs?.setString(_kPrefix + usn, jsonEncode(prefs.toJson()));
    notifyListeners();
  }

  /// Deletes preferences for [usn]. No-op if not found.
  Future<void> delete(String usn) async {
    if (_cache.remove(usn) == null) return;
    await _prefs?.remove(_kPrefix + usn);
    notifyListeners();
  }

  // ── Backup integration ────────────────────────────────────────────────────

  /// Serialises all DMR prefs as a JSON-encodable map for inclusion in the
  /// backup archive (section key: `'dmr_prefs'`).
  Map<String, dynamic> exportForBackup() => {
    for (final entry in _cache.entries) entry.key: entry.value.toJson(),
  };

  /// Restores DMR prefs from a backup payload.
  ///
  /// Merges with existing entries; entries not in the backup are untouched.
  /// Call after accounts are restored so USN → account mappings stay valid.
  Future<void> importFromBackup(Map<String, dynamic> payload) async {
    for (final entry in payload.entries) {
      final usn = entry.key;
      final raw = entry.value;
      if (raw is! Map<String, dynamic>) continue;
      try {
        _cache[usn] = DmrDevicePrefs.fromJson(raw);
        await _prefs?.setString(_kPrefix + usn, jsonEncode(raw));
      } catch (e) {
        debugPrint('[DmrPrefs] importFromBackup parse error for $usn: $e');
      }
    }
    notifyListeners();
  }
}
