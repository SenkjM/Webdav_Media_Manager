# 交接 · 漫画库分支（feat/manga-library）

> 总索引：[00-INDEX.md](00-INDEX.md) · 语义锁定：[99 §19](99-IN-PROGRESS.md) · 同步与备份：[08](08-SYNC-AND-BACKUP.md)
> 写于 2026-10-12 晚。接手前先读本文件，再读 00、99 §19、08。

## 1. 仓库规则（摘要，以 docs/00 为准）

- 开发前读 [00-INDEX.md](00-INDEX.md) 与 [99](99-IN-PROGRESS.md)；进行中的语义记在 99，完成后收进对应完整文档。
- 门槛：`flutter analyze` 干净 + `flutter test` 全过。Flutter 不在 PATH：`/workspace/flutter-sdk/bin/flutter`。
- 新 Dart 文件加 `// SPDX-License-Identifier: AGPL-3.0-or-later`（docs 不加）。
- 界面文案中文为模板（`app_zh.arb`，另有 `app_zh_TW` / `app_en`）。**gen-l10n 无 @ 元数据 → 占位参数按字母序生成**，调用时按字母序传参（「约 true」就是这么来的）。
- 提交前缀 `feat:` / `fix:` / `docs:`；分支提交日后会 squash。
- **未经用户明确同意：不推 main、不发 release。** 推非 main 分支可以。**Testbuild（`testbuild.yml` workflow_dispatch）只在用户要求时触发。**
- 命名用 **manga**（`Manga` / `mangaId` / `UserFolderRefKind.manga`），不用 book。

## 2. 漫画库锁定语义（完整见 99 §19）

- 同库 `music_library.db`；表 `manga_series` / `mangas` / `manga_pages` / `manga_progress`；`mangas.id` = 确定性 `mangaIdForRemote(网盘名, remotePath)`，`UNIQUE(source_name, remote_path)`。
- 抽屉顺序：文件夹 → 音乐库 → 歌单 → **漫画库** → 网络库 → 任务 → 设置（`home_tab_v025_manga_inserted` 迁移）。
- 漫画库 Tab：系列 / 单本 / 作者；单本多选 + 批量修改系列。
- 翻页方向：全局 `image_page_turn` + 每本 `mangas.page_turn`（null = 跟随全局）。
- 建立：网络库文件夹「扫描漫画文件」（递归容器）/「合并建立漫画」/「按目录批量建立」；单文件「加入漫画库」。建立深度与扫描深度独立（`mangaCreateWalkOptions`：子目录默认开、深度默认 5）。
- 批量任务：每文件内部重试至多 3 次；部分失败 → `TaskStatus.partial`「部分失败」（99 §19.10）。
- 同步 / 备份：99 §19.11 + 08（下面第 3 节有现状）。

## 3. 当前状态

| 提交 | 内容 | 备注 |
|------|------|------|
| `6734c4b` | 封面、视图模式、CBZ Range 流式/刮削、元数据编辑、manga_cache、文件夹移动/复制；批量部分失败 + 每文件 3 次重试 | 已 Testbuild #24 成功 |
| `24e9a1f` | 云端路径 `library/music/` · `library/manga/`（+ `progress.json`）· `library/folders/folders.json`（不兼容旧平铺）；漫画同步对照音乐（index + lib/seg/del、rev + 墓碑、增量/重建/整理/覆写/删除、一键/防抖/定时）；阅读进度每本较新 `updatedAt` 胜；文件夹整份快照 LWW；全部备份 v7（段 13 mangaLibrary、14 userFolders）；schema 15（`mangas.rev`、`deleted_mangas`、`local_meta`）；修「约 true」与预取测试 | 当时同步**全部格式**的页序 |
| `0e77127` | 页序改为仅本地缓存（同步与备份都不带）+ 散图缺页序时**打开即递归列目录重建** | **错误，不要发布**：散图的页表是建立时筛选出的成员集合（扩展名、深度、子目录开关、按目录模式只取本层），列目录无法复现；按目录模式下父目录会吞掉子书 |

- **Testbuild #25**（https://github.com/SenkjM/Webdav_Media_Manager/actions/runs/38256652621）跑在 `0e77127` 上，受上述错误影响，不能作为验收包。
- **stash `option4-wip`**（`git stash list` 可见，**不要 drop**）：未提交、**未验证**（analyze/test 被中断）。内容：
  - tag 18 复用：仅 `format == images` 的行在分片里携带页表；`MangaSyncRow` 对非 images 强制空页表。
  - 拉取：images 行替换本地页表且不 bump rev；CBZ 行不动本地页序。
  - `replaceMangaPages(..., {bumpRev = false})`；`MangaLibraryService.replacePages` 仅 images 时 bump；页数/封面未变则不改行。
  - 备份 v7 漫画段 `pages` 只导出 images 漫画的页行，恢复时写回。
  - 删除 `_prepareImages` 的打开时列目录兜底。
  - 测试：manga_sync_test（images 带页表 / CBZ 不带）、manga_library_test（syncRows、adopt、bump 规则）、备份往返断言 `pages`。
  - **docs/08 与 99 §19.11 还没按此改**（仍写着「页序只作本地缓存 + 打开时列目录」）。

## 4. 已接受的方向：两类漫画模型（**用户：「先不落地，看看行不行」——实施前必须再确认**）

- **A 类：散图（`format == images`）** = 一份显式的远端图片路径列表，成员集合就是数据。
  - 页表随同步分片（tag 18）与全部备份走；本地编辑页表 bump rev。
  - 新写入的页用**绝对路径**（阅读器已支持：`relPath` 以 `/` 开头即按绝对路径解析；旧的相对路径仍按 `remotePath` 解析，无需迁移）。
  - **锚点 id**：`remote_path` = 建立时的锚点目录（当前两种模式就是该目录），id / 同步键 / 文件夹软引用都不变；将来跨目录拼书取公共父目录或起始目录，冲突时加后缀或提示替换。
  - **一本只属于一个网盘账号**（`manga_pages` 无 source 列，阅读器单账号）。
  - 缓存：逐图 `PrefetchCache` bucket `images`（已是这样）。
  - `remote_missing`：锚点目录不存在，或读页失败时标记；单个子目录缺图不判整本缺失。
- **B 类：容器文件（CBZ/CBR/PDF/EPUB）** = 一个文件引用 + 解析出的元数据；页序由文件推出，**只作本地缓存**，写页序永不 bump rev。
  - 缓存：整文件 `manga_cache`（`CacheService.mangaFileForRemote`）+ `manga_cache/covers/<id>`。
  - `remote_missing`：文件不存在。
- **菜单分流**：`lib/screens/manga_library_screen.dart` `_mangaMore`（约 L605–660）的「缓存 / 清除缓存」用 `mangaFileForRemote(remotePath)`，对 A 类无意义 → 隐藏或改成「预取全部页 / 清除页缓存」；「刮削」只对 B 类（需确认当前是否已限制）。
- 不新增 `kind` 列：由 `format` 推出。

## 5. 下一步

1. **步骤 1（确认后做）**：`git stash apply stash^{/option4-wip}`（保留 stash）→ 跑完 analyze/test 补齐 → 菜单按类分流（缓存/刮削）→ 改 docs/08 与 99 §19.11 为两类模型 → `fix:` 提交 → 推分支 → 用户要求时再 Testbuild。
2. **步骤 2（独立功能，以后）**：跨目录拼书建立器（同一账号内选多目录/多图，存绝对路径 + 锚点，处理锚点冲突）。

## 6. 暂缓 / 待办

- 漫画封面不进全部备份归档。
- 没有漫画的空系列不写墓碑。
- README 功能行未更新。
- 99 §19 表头仍写 schema「13 → 14」，实际已到 15。
- 未真机验收。
