// ── OpenAPI settings widget (debug-only) ────────────────────────────────────
//
// Exported for use in settings_screen.dart. Shows OpenAPI server controls in
// debug builds only (wrapped in kDebugMode guard by the parent).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/rust_core_service.dart';
import '../utils/app_snack.dart';

/// Stateful widget that shows OpenAPI server controls in debug builds.
///
/// Displays:
/// - Enable/disable toggle (starts/stops the server)
/// - Bind mode selector (local 127.0.0.1 / global 0.0.0.0)
/// - Current port and bearer token (copyable)
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
  int _port = 7878; // default suggestion; 0 = OS-assigned
  String _token = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _enabled = RustCoreService.isOpenApiRunning();
    if (_enabled) {
      _port = RustCoreService.openApiPort();
      _token = RustCoreService.tokenGet() ?? '';
      _status = 'Running on port $_port';
    } else {
      _status = 'Server not running';
    }
  }

  void _toggle(bool value) {
    if (value) {
      final tok = RustCoreService.startOpenApi(port: _port);
      setState(() {
        _enabled = true;
        _port = RustCoreService.openApiPort();
        _token = tok;
        _status = 'Running on port $_port';
      });
    } else {
      RustCoreService.stopOpenApi();
      setState(() {
        _enabled = false;
        _token = '';
        _status = 'Server not running';
      });
    }
  }

  void _rotateToken() {
    final newTok = RustCoreService.tokenRotate();
    if (newTok != null) {
      setState(() {
        _token = newTok;
        _status = 'Token rotated';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        if (_enabled) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lan_outlined),
            title: const Text('Bind mode'),
            subtitle: const Text('local = 127.0.0.1, global = 0.0.0.0'),
            trailing: DropdownButton<int>(
              borderRadius: BorderRadius.circular(10),
              value: _port == 0 ? 7878 : _port,
              items: const [
                DropdownMenuItem(value: 7878, child: Text('Port 7878 (local)')),
                DropdownMenuItem(value: 8080, child: Text('Port 8080 (local)')),
                DropdownMenuItem(value: 0, child: Text('OS-assigned')),
              ],
              onChanged: (v) {
                if (v != null) {
                  RustCoreService.stopOpenApi();
                  final tok = RustCoreService.startOpenApi(port: v);
                  setState(() {
                    _port = RustCoreService.openApiPort();
                    _token = tok;
                    _status = 'Running on port $_port';
                  });
                }
              },
            ),
          ),
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
              'GET http://127.0.0.1:$_port/v1/library/tracks',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}
