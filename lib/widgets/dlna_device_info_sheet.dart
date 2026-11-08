import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/dlna_cast_service.dart';
import '../services/rust_core_service.dart';
import '../services/rust_dmr_prefs_service.dart';
import '../utils/app_snack.dart';

/// DLNA 设备详细信息 BottomSheet。
///
/// 显示设备详细字段（型号/制造商/USN/协议信息等），
/// 提供复制全部功能，**无「详细」折叠按钮**。
///
/// 「支持的协议信息」由 Core 的 `GetProtocolInfo` 实时读取
/// （[RustCoreService.dlnaSinkProtocolInfo]）；正在投屏时优先展示会话协商结果；
/// 旧版 `.so` 没有该符号时降级为只读展示，绝不崩溃。
class DlnaDeviceInfoSheet extends StatefulWidget {
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

  @override
  State<DlnaDeviceInfoSheet> createState() => _DlnaDeviceInfoSheetState();
}

/// 在 worker isolate 里读取设备 ConnectionManager 的 SinkProtocolInfo。
///
/// 这个函数必须是**顶层**函数：`Isolate.run` 的闭包如果写在 widget 方法里，
/// 会连同外层异步上下文一起捕获（其中包含 `State`：Completer、监听器、
/// BuildContext），dart:isolate 拒绝发送，报
/// `Illegal argument in isolate message: object is unsendable`。
/// 放在顶层的闭包上下文里只有可发送的 `location` 字符串。
Future<String?> _readSinkProtocolInfoOffMain(String location) =>
    Isolate.run(() => RustCoreService.dlnaSinkProtocolInfo(location));

class _DlnaDeviceInfoSheetState extends State<DlnaDeviceInfoSheet> {
  /// 设备支持（Sink）的 protocolInfo 条目，Rust 返回的 CSV 已拆好。
  List<String> _sink = const [];

  /// 当前投屏会话协商出的 protocolInfo（null = 没有活动会话）。
  String? _sessionInfo;

  /// 读取中 / 读取失败的原因（null = 正常）。
  bool _loading = true;
  String? _error;

  /// 递增请求序号，丢弃过期响应（用户连点刷新时）。
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    // 会话协商结果是 Rust 已确认可播放的协议，优先展示。
    _sessionInfo = context.read<DlnaCastService>().protocolInfo;
    unawaited(_loadProtocolInfo());
  }

  /// 向 Rust 读取设备 ConnectionManager 的 SinkProtocolInfo。
  ///
  /// 读不到时只降级展示，不抛错：老版本 `libwdmm_ffi.so` 没有这个符号。
  Future<void> _loadProtocolInfo() async {
    final seq = ++_requestSeq;
    final location = widget.renderer.location;

    String? raw;
    try {
      // SOAP 往返会阻塞当前 isolate，必须放到 worker isolate。
      raw = await _readSinkProtocolInfoOffMain(location);
    } catch (e) {
      debugPrint('[DLNA] sink protocol_info request failed: $e');
      raw = null;
    }
    if (!mounted || seq != _requestSeq) return;

    var sink = const <String>[];
    String? error;
    if (raw == null || raw.isEmpty) {
      error = '当前核心库未提供协议信息接口';
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException('not a map');
        if (decoded['ok'] == false) {
          final message = decoded['error']?.toString() ?? '';
          error = message.isEmpty ? '读取设备协议信息失败' : message;
        } else {
          sink = _splitCsv(decoded['sink']?.toString() ?? '');
          if (sink.isEmpty) error = '设备未上报协议信息';
        }
      } catch (e) {
        debugPrint('[DLNA] sink protocol_info parse failed: $e');
        error = '协议信息解析失败';
      }
    }

    setState(() {
      _sink = sink;
      _error = error;
      _loading = false;
    });
  }

  Future<void> _refreshProtocolInfo() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _loadProtocolInfo();
  }

  /// 实际展示的协议条目：Rust 实时结果 > 发现阶段的 SSDP 结果。
  List<String> get _displayProtocols {
    if (_sink.isNotEmpty) return _sink;
    return widget.renderer.sinkProtocolInfo ?? const [];
  }

  /// 拆分 protocolInfo CSV（Rust 返回 `http-get:*:video/mp4:*,...`）。
  List<String> _splitCsv(String raw) {
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  /// 构造用于复制的完整信息文本（原始 MIME/protocolInfo）。
  String _buildCopyText() {
    final buf = StringBuffer();
    final pref = widget.dmrPrefs?[widget.renderer.usn];
    final renderer = widget.renderer;
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
    if (_sessionInfo != null && _sessionInfo!.isNotEmpty) {
      buf.writeln('当前会话协商: $_sessionInfo');
    }
    final protocols = _displayProtocols;
    if (protocols.isEmpty) {
      buf.writeln(_loading ? '(读取中)' : (_error ?? '(未加载)'));
    } else {
      for (final proto in protocols) {
        buf.writeln('  $proto');
      }
      if (_error != null) buf.writeln('(${_error!})');
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
    final renderer = widget.renderer;
    final pref = widget.dmrPrefs?[renderer.usn];
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

            // 标题行：设备名称 + 刷新/复制按钮
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
                  // 刷新协议信息
                  IconButton(
                    icon: Icon(Icons.refresh, color: scheme.onSurfaceVariant),
                    onPressed: _loading ? null : _refreshProtocolInfo,
                    tooltip: '刷新协议信息',
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
                  _buildProtocolInfoSection(scheme, textTheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 协议信息区域：会话协商结果 + Rust 实时 SinkProtocolInfo 列表。
  Widget _buildProtocolInfoSection(
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final session = _sessionInfo;
    final protocols = _displayProtocols;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session != null && session.isNotEmpty) ...[
            Text(
              '当前会话协商: $session',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_loading)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '正在读取…',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else if (protocols.isEmpty)
            Text(
              _error ?? '设备未上报协议信息',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            if (_error != null) ...[
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
              const SizedBox(height: 8),
            ],
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
        ],
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
