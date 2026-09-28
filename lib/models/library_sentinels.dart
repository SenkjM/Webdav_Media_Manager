/// Stable non-user-facing keys used for derived library group names.
const kUncategorizedGenre = '__wdmm_uncategorized__';
const kLegacyUncategorizedGenre = '未分类';

bool isUncategorizedGenre(String value) =>
    value == kUncategorizedGenre || value == kLegacyUncategorizedGenre;
