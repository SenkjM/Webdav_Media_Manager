import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 图片查看设置。网络库查看器点中间、设置里「流式传输」下的「图片查看」
/// 都进这一页，读写的是同一组 [SettingsService] 偏好，没有第二套模型。
class ImageSettingsScreen extends StatelessWidget {
  const ImageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.nearBlack,
      appBar: AppBar(title: Text(l10n.imageViewer)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.slideshow_outlined),
            title: Text(l10n.imageSlideshow),
            subtitle: Text(l10n.imageSlideshowHint),
            value: settings.imageSlideshowEnabled,
            onChanged: settings.setImageSlideshowEnabled,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined),
            title: Text(l10n.imageSlideshowInterval),
            subtitle: Text(
              l10n.imageSlideshowSeconds(
                settings.imageSlideshowIntervalSeconds,
              ),
            ),
          ),
          Slider(
            min: SettingsService.minImageSlideshowSeconds.toDouble(),
            max: SettingsService.maxImageSlideshowSeconds.toDouble(),
            divisions:
                SettingsService.maxImageSlideshowSeconds -
                SettingsService.minImageSlideshowSeconds,
            value: settings.imageSlideshowIntervalSeconds.toDouble(),
            label: l10n.imageSlideshowSeconds(
              settings.imageSlideshowIntervalSeconds,
            ),
            onChanged: (v) =>
                settings.setImageSlideshowIntervalSeconds(v.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.repeat),
            title: Text(l10n.imageSlideshowLoop),
            subtitle: Text(l10n.imageSlideshowLoopHint),
            value: settings.imageSlideshowLoop,
            onChanged: settings.setImageSlideshowLoop,
          ),
          const Divider(height: 32),
          Text(
            l10n.imageFit,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: SettingsService.imageFitContain,
                label: Text(l10n.imageFitContain),
                icon: const Icon(Icons.fit_screen_outlined),
              ),
              ButtonSegment(
                value: SettingsService.imageFitCover,
                label: Text(l10n.imageFitCover),
                icon: const Icon(Icons.crop),
              ),
            ],
            selected: {settings.imageFit},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              settings.setImageFit(next.first);
            },
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.imagePrefetchCount),
            subtitle: Text(l10n.imagePrefetchHint),
          ),
          Slider(
            min: SettingsService.minImagePrefetchCount.toDouble(),
            max: SettingsService.maxImagePrefetchCount.toDouble(),
            divisions:
                SettingsService.maxImagePrefetchCount -
                SettingsService.minImagePrefetchCount,
            value: settings.imagePrefetchCount.toDouble(),
            label: '${settings.imagePrefetchCount}',
            onChanged: (v) => settings.setImagePrefetchCount(v.round()),
          ),
          const Divider(height: 32),
          Text(
            l10n.imageScanSubdirs,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.account_tree_outlined),
            title: Text(l10n.imageScanSubdirs),
            subtitle: Text(l10n.imageScanSubdirsHint),
            value: settings.imageScanSubdirs,
            onChanged: settings.setImageScanSubdirs,
          ),
        ],
      ),
    );
  }
}
