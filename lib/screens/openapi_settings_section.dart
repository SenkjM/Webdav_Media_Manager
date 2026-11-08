// ── OpenAPI settings widget (debug-only) ────────────────────────────────────
//
// Exported for use in settings_screen.dart. Shows OpenAPI server controls in
// debug builds only (wrapped in kDebugMode guard by the parent).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/rust_core_service.dart';
import '../utils/app_snack.dart';

/// Stateful widget that shows OpenAPI server controls in debug builds.
///
/// Displays:
/// - Enable/disable toggle (starts/stops the server)
/// - Preferred listen port (presets + custom) and actual bound port echo
/// - Current bearer token (copyable)
///
/// The server is managed by `wdmm_openapi_start/stop` FFI exports via
/// [RustCoreService].  This is debug-only per Round 7 brief (§4).
class OpenApiSettingsSection extends StatefulWidget {
  const OpenApiSettingsSection({super.key});

  @override
  State<OpenApiSettingsSection> createState() =>
      _OpenApiSettingsSectionState();
}

class _OpenApiSettingsSectionState extends State<OpenApiSettingsSection> {
  bool _enabled = false;
  /// Port requested when starting. `0` = OS-assigned.
  int _preferredPort = 7878;
  /// Actual listen port reported by Rust (`-1` / `0` = unknown / not running).
  int _port = -1;
  String _token = '';
  String _status = '';
  late final TextEditingController _customPortCtrl;

  static const _presets = <int>[7878, 8080, 0];

  @override
  void initState() {
    super.initState();
    _customPortCtrl = TextEditingController();
    _enabled = RustCoreService.isOpenApiRunning();
    if (_enabled) {
      final p = RustCoreService.openApiPort();
      _port = p;
      if (_presets.contains(p)) {
        _preferredPort = p;
      } else if (p > 0) {
        _preferredPort = p;
        _customPortCtrl.text = '$p';
      } else {
        _preferredPort = 0;
      }
      _token = RustCoreService.tokenGet() ?? '';
      _status = _statusFor(p);
    } else {
      _status = 'Server not running';
    }
  }

  @override
  void dispose() {
    _customPortCtrl.dispose();
    super.dispose();
  }

  String _statusFor(int actualPort) {
    if (actualPort > 0) return 'Running on port $actualPort';
    return 'Running (port unknown)';
  }

  void _applyStart(int requestPort) {
    final tok = RustCoreService.startOpenApi(port: requestPort);
    final p = RustCoreService.openApiPort();
    setState(() {
      _enabled = true;
      _preferredPort = requestPort;
      _port = p;
      _token = tok;
      _status = _statusFor(p);
      if (requestPort > 0 && !_presets.contains(requestPort)) {
        _customPortCtrl.text = '$requestPort';
      }
    });
  }

  void _toggle(bool value) {
    if (value) {
      _applyStart(_preferredPort);
    } else {
      RustCoreService.stopOpenApi();
      setState(() {
        _enabled = false;
        _port = -1;
        _token = '';
        _status = 'Server not running';
      });
    }
  }

  void _onPreset(int? v) {
    if (v == null) return;
    RustCoreService.stopOpenApi();
    _applyStart(v);
  }

  void _applyCustomPort() {
    final raw = _customPortCtrl.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1 || parsed > 65535) {
      AppSnack.show(context, 'Port must be 1–65535');
      return;
    }
    RustCoreService.stopOpenApi();
    _applyStart(parsed);
  }

  void _rotateToken() {
    final newTok = RustCoreService.tokenRotate();
    if (newTok != null) {
      setState(() {
        _token = newTok;
        _status = 'Token rotated · ${_port > 0 ? "port $_port" : "port unknown"}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final actualEcho = !_enabled
        ? '—'
        : (_port > 0 ? '$_port' : 'waiting / unknown');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.api_outlined),
          title: const Text('Enable OpenAPI Server'),
          subtitle: Text(_status),
          value: _enabled,
          onChanged: _toggle,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Actual listen port'),
          subtitle: Text(
            _enabled && _preferredPort == 0
                ? 'OS-assigned → $actualEcho'
                : actualEcho,
          ),
          trailing: Text(
            actualEcho,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lan_outlined),
          title: const Text('Preferred port'),
          subtitle: const Text('Presets; 0 = OS-assigned (see actual above)'),
          trailing: DropdownButton<int>(
            borderRadius: BorderRadius.circular(10),
            value: _presets.contains(_preferredPort) ? _preferredPort : null,
            hint: Text(
              _preferredPort > 0 ? 'Custom $_preferredPort' : 'Custom',
            ),
            items: const [
              DropdownMenuItem(value: 7878, child: Text('7878')),
              DropdownMenuItem(value: 8080, child: Text('8080')),
              DropdownMenuItem(value: 0, child: Text('OS-assigned (0)')),
            ],
            onChanged: _onPreset,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: TextField(
                  controller: _customPortCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Custom port',
                    hintText: '1–65535',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _applyCustomPort(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _applyCustomPort,
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
        if (_enabled) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('Bearer token'),
            subtitle: Text(
              _token.isNotEmpty ? _token : '(none)',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kDebugMode)
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Show token',
                    onPressed: _token.isNotEmpty
                        ? () => AppSnack.show(context, 'Token: $_token')
                        : null,
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Rotate token',
                  onPressed: _rotateToken,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Usage: Authorization: Bearer <token>  →  '
              'GET http://127.0.0.1:${_port > 0 ? _port : "<port>"}/v1/library/tracks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}