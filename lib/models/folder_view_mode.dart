import '../l10n/generated/app_localizations.dart';

/// Folder-tab browse density: list, or N-column grid (2–5).
enum FolderViewMode {
  list,
  grid2,
  grid3,
  grid4,
  grid5,
}

extension FolderViewModeX on FolderViewMode {
  String get storageKey => switch (this) {
        FolderViewMode.list => 'list',
        FolderViewMode.grid2 => 'grid2',
        FolderViewMode.grid3 => 'grid3',
        FolderViewMode.grid4 => 'grid4',
        FolderViewMode.grid5 => 'grid5',
      };

  /// Null means list view; otherwise grid cross-axis count.
  int? get crossAxisCount => switch (this) {
        FolderViewMode.list => null,
        FolderViewMode.grid2 => 2,
        FolderViewMode.grid3 => 3,
        FolderViewMode.grid4 => 4,
        FolderViewMode.grid5 => 5,
      };

  bool get isGrid => crossAxisCount != null;

  String label(AppLocalizations l10n) => switch (this) {
        FolderViewMode.list => l10n.folderViewList,
        FolderViewMode.grid2 => l10n.folderViewGridColumns(2),
        FolderViewMode.grid3 => l10n.folderViewGridColumns(3),
        FolderViewMode.grid4 => l10n.folderViewGridColumns(4),
        FolderViewMode.grid5 => l10n.folderViewGridColumns(5),
      };

  static FolderViewMode fromStorageKey(String? key) {
    switch (key) {
      case 'grid2':
        return FolderViewMode.grid2;
      case 'grid3':
        return FolderViewMode.grid3;
      case 'grid4':
        return FolderViewMode.grid4;
      case 'grid5':
        return FolderViewMode.grid5;
      case 'list':
      default:
        return FolderViewMode.list;
    }
  }
}
