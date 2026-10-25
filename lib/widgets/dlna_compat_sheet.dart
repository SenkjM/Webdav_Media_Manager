import 'package:flutter/material.dart';

import '../services/dlna_cast_service.dart';
import '../services/rust_dmr_prefs_service.dart';
import '../utils/app_snack.dart';

/// DLNA 设备兼容性设置 BottomSheet。
///
/// 提供：
/// - 显示名称覆盖（优先于 friendlyName）
/// - 单文件直通 (forceDirect) 开关（与 HLS 转码互斥）
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

class _DlnaCompatSheetState extends State<DlnaCompatSheet> {
  late TextEditingController _nameController;
  late bool _forceDirect;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final pref = widget.dmrPrefs[widget.renderer.usn];
    _nameController = TextEditingController(
      text: pref?.overrideName ?? '',
    );
    _forceDirect = pref?.forceDirect ?? false;
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

                  // 单文件直通开关
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
                            onChanged: (val) => setState(() => _forceDirect = val),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '单文件直通',
                              style: textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _forceDirect
                                    ? '已启用：直接投放原始文件（不经过 HLS 转码）'
                                    : '已禁用：通过 HLS 代理投屏（支持转码/兼容性）',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 0, bottom: 8),
                            child: Text(
                              '注意：单文件直通与 HLS 转码互斥。启用后将跳过所有容器重封装和编码转换。',
                              style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

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
