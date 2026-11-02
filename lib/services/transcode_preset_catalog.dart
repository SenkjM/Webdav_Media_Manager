import 'dart:convert';

import 'rust_core_service.dart';

/// 转码预设选择项（数据库行在 UI 侧的最小投影）。
class TranscodePresetOption {
  const TranscodePresetOption({required this.id, required this.label});

  /// 数据库主键（如 `balanced`、`dlna-compat`）。
  final String id;

  /// 展示名称：内置预设用中文名，自定义预设用数据库里的 label。
  final String label;
}

/// 从 Core 数据库读取可选转码预设，供 DLNA 相关界面复用。
///
/// 直通（`passthrough`）**不是**转码预设：它只由「直通（不转码）」兼容开关
/// 表达（`force_direct`），因此这里永远排除。选项本身来自数据库
/// （`transcode_presets` 表，含用户自定义预设），FFI 不可用时回退到内置 id，
/// 保证设置页在旧版 `.so` 上仍可用。
class TranscodePresetCatalog {
  const TranscodePresetCatalog._();

  /// 直通预设 id：只作为兼容开关存在，不出现在转码预设选项里。
  static const String passthroughId = 'passthrough';

  /// 内置预设的中文展示名称（仅 UI 文案；转码参数始终以数据库为准）。
  static const Map<String, String> _builtinLabels = {
    'balanced': '均衡',
    'dlna-compat': '高兼容',
    'high': '高画质',
    'audio-only': '仅音频',
  };

  /// FFI 不可用时的回退选项（与数据库种子的内置预设 id 一致，排除直通）。
  static const List<TranscodePresetOption> fallback = [
    TranscodePresetOption(id: 'balanced', label: '均衡'),
    TranscodePresetOption(id: 'dlna-compat', label: '高兼容'),
    TranscodePresetOption(id: 'high', label: '高画质'),
    TranscodePresetOption(id: 'audio-only', label: '仅音频'),
  ];

  /// 读取数据库中的转码预设（已排除直通、按 `sort_order` 排序）。
  ///
  /// 任何 FFI / 解析失败都回退到 [fallback]；结果保证非空。
  static List<TranscodePresetOption> load() {
    final raw = RustCoreService.transcodePresetsJson();
    if (raw == null || raw.isEmpty || raw.startsWith('error:')) {
      return fallback;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return fallback;
      final rows = <(int, TranscodePresetOption)>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString() ?? '';
        if (id.isEmpty || id == passthroughId) continue;
        final rawLabel = entry['label']?.toString() ?? '';
        final label = _builtinLabels[id] ?? (rawLabel.isEmpty ? id : rawLabel);
        final order = entry['sort_order'] as int? ?? 0;
        rows.add((order, TranscodePresetOption(id: id, label: label)));
      }
      if (rows.isEmpty) return fallback;
      rows.sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final row in rows) row.$2];
    } catch (_) {
      return fallback;
    }
  }

  /// 在 [options] 中按 id 查展示名称，找不到时返回 id 本身。
  static String labelOf(List<TranscodePresetOption> options, String id) {
    for (final option in options) {
      if (option.id == id) return option.label;
    }
    return _builtinLabels[id] ?? id;
  }
}
