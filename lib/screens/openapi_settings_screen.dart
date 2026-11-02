import 'package:flutter/material.dart';

import 'openapi_settings_section.dart';

/// Full-page wrapper around [OpenApiSettingsSection].
///
/// Previously OpenAPI settings were embedded inside the debug-only block
/// on the main settings screen. Now they live on their own sub-page
/// reachable by all builds.
class OpenApiSettingsScreen extends StatelessWidget {
  const OpenApiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenAPI'),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: OpenApiSettingsSection(),
      ),
    );
  }
}
