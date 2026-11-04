import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/dlna_cast_service.dart';
import '../services/rust_dmr_prefs_service.dart';
import '../services/settings_service.dart';
import '../services/transcode_preset_catalog.dart';
import '../utils/app_snack.dart';

/// DLNA 设备兼容性设置 BottomSheet。
///
/// 提供：
/// - 显示名称覆盖（优先于 friendlyName）
/// - 直通（不转码）兼容开关 `forceDirect`：初始值 = 设备级覆盖 > 全局「默认直通」
/// - 转码预设选择（仅在 forceDirect=false 时有效）
///
/// 设置通过 USN 键存储在 `RustDmrPrefsService` / Core `dmr_prefs.db`。
class DlnaCompatSheet extends StatefulWidget {
  const DlnaCompatSheet({
    super.key,
    required this.renderer,
    required this.dmrPrefs,
  });

  final DlnaRenderer renderer;
  final RustDmrPrefsService dmrPrefs;

  /// 弹出兼容性设置 Sheet。
  ///
  /// 可在以下场景触发：
  /// - 首次投屏（可选提示）
  /// - 投屏错误后（用户点击「兼容性设置」）
  /// - 设备列表长按或设置按钮
  static Future<void> show(
    BuildContext context,
    DlnaRenderer renderer,
    RustDmrPrefsService dmrPrefs,
  ) async {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DlnaCompatSheet(
        renderer: renderer,
        dmrPrefs: dmrPrefs,
      ),
    );
  }

  @override
  State<DlnaCompatSheet> createState() => _DlnaCompatSheetState();
}

// 转码预设选项来自 Core 数据库（排除直通），不再硬编码预设列表。
class _DlnaCompatSheetState extends State<DlnaCompatSheet> {
  late TextEditingController _nameController;
  late bool _forceDirect;
  // null means "follow app default"
  String? _presetId;
  // 数据库里的可选转码预设（不含 passthrough）。
  late List<TranscodePresetOption> _presets;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _presets = TranscodePresetCatalog.load();
    final pref = widget.dmrPrefs[widget.renderer.usn];
    _nameController = TextEditingController(
      text: pref?.overrideName ?? '',
    );
    // 初始值：设备级覆盖优先，否则跟随设置页「默认直通」；仅初始值，可改。
    _forceDirect =
        pref?.forceDirect ?? context.read<SettingsService>().dlnaDefaultDirect;
    // 直通不是转码预设：历史遗留的 passthrough 值按「跟随全局默认」处理。
    final savedPreset = pref?.presetId;
    _presetId = (savedPreset != null &&
            savedPreset.isNotEmpty &&
            savedPreset != TranscodePresetCatalog.passthroughId)
        ? savedPreset
        : null; // null = follow global default
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 保存设置到 Core dmr_prefs.db。
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final overrideName = _nameController.text.trim();
    final pref = DmrPreference(
      usn: widget.renderer.usn,
      forceDirect: _forceDirect,
      overrideName: overrideName.isEmpty ? null : overrideName,
      // 直通时 preset_id 必须为 null；被删除的自定义预设也回退到全局默认。
      presetId: _forceDirect || !_presets.any((p) => p.id == _presetId)
          ? null
          : _presetId,
    );

    final ok = await widget.dmrPrefs.save(pref);
    if (!mounted) return;

    if (ok) {
      AppSnack.show(context, '已保存设备兼容性设置');
      Navigator.pop(context);
    } else {
      AppSnack.show(context, '保存失败，请重试');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final globalDefault =
        context.watch<SettingsService>().dlnaDefaultTranscodePreset;
    final presetIds = {for (final p in _presets) p.id};
    final selectedPreset = presetIds.contains(_presetId) ? _presetId : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拖动把手
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题行
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.tune, color: scheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '兼容性设置',
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                    onPressed: () => Navigator.pop(context),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 设置表单
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 设备名称覆盖
                  Text(
                    '设备名称',
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: widget.renderer.friendlyName,
                      labelText: '自定义显示名称（可选）',
                      helperText: '留空则使用设备原始名称',
                      border: const OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 直通（不转码）兼容开关
                  Text(
                    '投屏模式',
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: scheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            value: _forceDirect,
                            onChanged: (val) =>
                                setState(() => _forceDirect = val),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '直通：不转码',
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 转码预设（仅 HLS 模式下有意义）
                  if (!_forceDirect) ...[
                    const SizedBox(height: 20),
                    Text(
                      '转码预设',
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '为本设备选择预设',
                        helperText: '留空则使用全局默认预设',
                      ),
                      initialValue: selectedPreset,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            '全局默认（${TranscodePresetCatalog.labelOf(_presets, globalDefault)}）',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        for (final preset in _presets)
                          DropdownMenuItem<String?>(
                            value: preset.id,
                            child: Text(preset.label),
                          ),
                      ],
                      onChanged: (v) => setState(() => _presetId = v),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 保存按钮
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _saving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scheme.onPrimary,
                              ),
                            ),
                          )
                        : const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
