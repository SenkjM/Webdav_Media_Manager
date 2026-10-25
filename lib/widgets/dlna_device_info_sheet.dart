import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/dlna_cast_service.dart';
import '../services/rust_dmr_prefs_service.dart';
import '../utils/app_snack.dart';

/// DLNA 设备详细信息 BottomSheet。
///
/// 显示设备详细字段（型号/制造商/USN/协议信息等），
/// 提供复制全部功能，**无「详细」折叠按钮**。
class DlnaDeviceInfoSheet extends StatelessWidget {
  const DlnaDeviceInfoSheet({
    super.key,
    required this.renderer,
    this.dmrPrefs,
  });

  final DlnaRenderer renderer;
  final RustDmrPrefsService? dmrPrefs;

  /// 弹出信息详情 Sheet。
  static Future<void> show(
    BuildContext context,
    DlnaRenderer renderer, {
    RustDmrPrefsService? dmrPrefs,
  }) async {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DlnaDeviceInfoSheet(
        renderer: renderer,
        dmrPrefs: dmrPrefs,
      ),
    );
  }

  /// 构造用于复制的完整信息文本（原始 MIME/protocolInfo）。
  String _buildCopyText() {
    final buf = StringBuffer();
    final pref = dmrPrefs?[renderer.usn];
    final displayName = pref?.overrideName?.isNotEmpty == true
        ? pref!.overrideName!
        : renderer.friendlyName;

    buf.writeln('【DLNA 设备信息】');
    buf.writeln();
    buf.writeln('名称: $displayName');
    if (pref?.overrideName != null) {
      buf.writeln('原始名称: ${renderer.friendlyName}');
    }
    if (renderer.modelName != null) {
      buf.writeln('型号: ${renderer.modelName}');
    }
    if (renderer.manufacturer != null) {
      buf.writeln('制造商: ${renderer.manufacturer}');
    }
    if (renderer.modelNumber != null) {
      buf.writeln('型号编号: ${renderer.modelNumber}');
    }
    buf.writeln('IP 地址: ${renderer.host}');
    buf.writeln('USN: ${renderer.usn}');
    buf.writeln('Location: ${renderer.location}');
    buf.writeln();

    // 原始 protocolInfo / MIME 支持
    buf.writeln('【支持的协议信息 (SinkProtocolInfo)】');
    final protocols = renderer.sinkProtocolInfo;
    if (protocols == null || protocols.isEmpty) {
      buf.writeln('(未加载)');
    } else {
      for (final proto in protocols) {
        buf.writeln('  $proto');
      }
    }

    return buf.toString();
  }

  /// 复制全部到剪贴板并提示用户。
  Future<void> _copyAll(BuildContext context) async {
    final text = _buildCopyText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppSnack.show(context, '已复制设备详细信息到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pref = dmrPrefs?[renderer.usn];
    final displayName = pref?.overrideName?.isNotEmpty == true
        ? pref!.overrideName!
        : renderer.friendlyName;

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

            // 标题行：设备名称 + 复制按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.tv, color: scheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayName,
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 复制全部按钮
                  IconButton(
                    icon: Icon(Icons.copy_all, color: scheme.onSurfaceVariant),
                    onPressed: () => _copyAll(context),
                    tooltip: '复制全部',
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

            // 信息列表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pref?.overrideName != null) ...[
                    _InfoRow(
                      label: '原始名称',
                      value: renderer.friendlyName,
                      scheme: scheme,
                      textTheme: textTheme,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (renderer.modelName != null) ...[
                    _InfoRow(
                      label: '型号',
                      value: renderer.modelName!,
                      scheme: scheme,
                      textTheme: textTheme,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (renderer.manufacturer != null) ...[
                    _InfoRow(
                      label: '制造商',
                      value: renderer.manufacturer!,
                      scheme: scheme,
                      textTheme: textTheme,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (renderer.modelNumber != null) ...[
                    _InfoRow(
                      label: '型号编号',
                      value: renderer.modelNumber!,
                      scheme: scheme,
                      textTheme: textTheme,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _InfoRow(
                    label: 'IP 地址',
                    value: renderer.host,
                    scheme: scheme,
                    textTheme: textTheme,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    label: 'USN',
                    value: renderer.usn,
                    scheme: scheme,
                    textTheme: textTheme,
                    monospace: true,
                  ),
                  const SizedBox(height: 16),

                  // 协议信息区域
                  Text(
                    '支持的协议信息',
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ProtocolInfoSection(
                    renderer: renderer,
                    scheme: scheme,
                    textTheme: textTheme,
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

/// 单行信息显示。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.scheme,
    required this.textTheme,
    this.monospace = false,
  });

  final String label;
  final String value;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
      ],
    );
  }
}

/// 协议信息区域（SinkProtocolInfo 列表）。
class _ProtocolInfoSection extends StatelessWidget {
  const _ProtocolInfoSection({
    required this.renderer,
    required this.scheme,
    required this.textTheme,
  });

  final DlnaRenderer renderer;
  final ColorScheme scheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final protocols = renderer.sinkProtocolInfo;

    if (protocols == null || protocols.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '(未加载)',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < protocols.length; i++) ...[
            Text(
              protocols[i],
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            if (i < protocols.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
