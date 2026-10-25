import 'dart:convert';
import 'dart:io';

import 'rust_core_service.dart';

class DmrPreference {
  const DmrPreference({
    required this.usn,
    required this.forceDirect,
    this.overrideName,
    this.updatedAt,
  });

  final String usn;
  final bool forceDirect;
  final String? overrideName;
  final String? updatedAt;

  factory DmrPreference.fromJson(Map<String, dynamic> json) => DmrPreference(
        usn: json['usn'] as String? ?? '',
        forceDirect: json['force_direct'] == true,
        overrideName: json['override_name'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'usn': usn,
        'force_direct': forceDirect,
        if (overrideName != null && overrideName!.isNotEmpty)
          'override_name': overrideName,
      };
}

/// USN-keyed DMR preferences owned by WDMM-core's independent database.
class RustDmrPrefsService {
  RustDmrPrefsService();

  bool _initialized = false;
  final Map<String, DmrPreference> _prefs = <String, DmrPreference>{};

  DmrPreference? operator [](String usn) => _prefs[usn];
  Iterable<DmrPreference> get values => _prefs.values;

  Future<void> init(String documentsPath) async {
    if (_initialized) return;
    if (!Platform.isAndroid) return;
    final path = '$documentsPath/dmr_prefs.db';
    final result = RustCoreService.dmrPrefsInit(path);
    if (result == null || result.startsWith('error:')) return;
    _initialized = true;
    await reload();
  }

  Future<void> reload() async {
    final raw = RustCoreService.dmrPrefsList();
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _prefs
        ..clear()
        ..addEntries(
          decoded.whereType<Map>().map((row) {
            final pref = DmrPreference.fromJson(Map<String, dynamic>.from(row));
            return MapEntry(pref.usn, pref);
          }),
        );
    } catch (_) {}
  }

  Future<bool> save(DmrPreference preference) async {
    final result = RustCoreService.dmrPrefsUpsert(jsonEncode(preference.toJson()));
    if (result == null || result.startsWith('error:')) return false;
    _prefs[preference.usn] = preference;
    return true;
  }

  Future<bool> remove(String usn) async {
    final result = RustCoreService.dmrPrefsDelete(usn);
    if (result == null || result.startsWith('error:')) return false;
    _prefs.remove(usn);
    return true;
  }
}
