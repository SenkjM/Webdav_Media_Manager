import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/rust_dlna_cast_service.dart';

/// DLNA 设备选择 BottomSheet。
///
/// 使用 [DlnaDeviceSheet.show] 静态方法弹出，用户选择渲染器后返回
/// [DlnaRenderer]，取消或关闭时返回 null。
class DlnaDeviceSheet extends StatefulWidget {
  const DlnaDeviceSheet({super.key});

  /// 弹出设备选择 Sheet，返回用户所选的 [DlnaRenderer]，取消时返回 null。
  static Future<DlnaRenderer?> show(BuildContext context) async {
    return showModalBottomSheet<DlnaRenderer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const DlnaDeviceSheet(),
    );
  }

  @override
  State<DlnaDeviceSheet> createState() => _DlnaDeviceSheetState();
}

class _DlnaDeviceSheetState extends State<DlnaDeviceSheet> {
  /// 超时计时器：4 秒后若无设备则显示"未找到设备"提示
  Timer? _timeoutTimer;

  /// 是否已超时且仍无设备
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    // 打开时立刻开始发现
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final castService = context.read<RustDlnaCastService>();
      castService.startDiscovery();
      _startTimeout();
    });
  }

  /// 启动 4 秒超时计时器
  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timedOut = false;
    _timeoutTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final castService = context.read<RustDlnaCastService>();
      // 已发现到设备则不显示超时提示
      if (castService.discovered.isEmpty) {
        setState(() => _timedOut = true);
      }
    });
  }

  /// 重新搜索：重置超时状态并重新发起发现
  void _retry() {
    final castService = context.read<RustDlnaCastService>();
    castService.stopDiscovery();
    castService.startDiscovery();
    setState(() => _timedOut = false);
    _startTimeout();
  }

  /// 用户选择了一台渲染器
  void _selectRenderer(BuildContext ctx, DlnaRenderer renderer) {
    final castService = context.read<RustDlnaCastService>();
    castService.stopDiscovery();
    Navigator.pop(ctx, renderer);
  }

  /// 关闭 Sheet
  void _close(BuildContext ctx) {
    final castService = context.read<RustDlnaCastService>();
    castService.stopDiscovery();
    Navigator.pop(ctx);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final castService = context.watch<RustDlnaCastService>();
    final scheme = Theme.of(context).colorScheme;
    final discovered = castService.discovered;
    final isDiscovering = castService.state == DlnaCastState.discovering;

    return SafeArea(
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

          // 标题行 + 关闭按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              children: [
                Icon(Icons.cast, color: scheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '选择投屏设备',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                  onPressed: () => _close(context),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 内容区：列表 / 加载中 / 未找到设备
          if (discovered.isNotEmpty)
            // 发现了设备 → 渲染列表
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: discovered.length,
              itemBuilder: (ctx, i) {
                final renderer = discovered[i];
                return ListTile(
                  leading: Icon(
                    Icons.tv,
                    color: scheme.primary,
                  ),
                  title: Text(
                    renderer.friendlyName,
                    style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    renderer.host,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                  onTap: () => _selectRenderer(context, renderer),
                );
              },
            )
          else if (_timedOut)
            // 超时且无设备 → 显示提示 + 重新搜索
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tv_off_outlined,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '未找到 DLNA 设备',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '请确认电视或音箱已开启并连接同一局域网',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.tonal(
                    onPressed: _retry,
                    child: const Text('重新搜索'),
                  ),
                ],
              ),
            )
          else
            // 发现中（尚未超时）→ 显示加载指示器
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '正在搜索设备…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          // 底部搜索中状态行（发现了设备后仍继续搜索）
          if (discovered.isNotEmpty && isDiscovering)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '仍在搜索更多设备…',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
