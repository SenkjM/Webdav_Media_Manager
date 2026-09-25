# 01 · 数据结构：本地与云端文件的语义约定

> 编号 01 · 总索引：[00-INDEX.md](00-INDEX.md)

本文只讲**语义约定**（一个键代表什么、什么算「有文件」、文件叫什么名字）。同步流程与路径规则见 [08](08-SYNC-AND-BACKUP.md)，各功能的用户行为见对应功能块文档。

## 1. 曲目身份 `music_id`

实现：`lib/utils/track_identity.dart`。**稳定离线主键，SHA-1 hex**：

| 类型 | 规则 |
|------|------|
| 普通曲目 | `sha1(accountId + '\0' + normalizeRemotePath(remotePath))` |
| CUE 虚拟分片 | `sha1(accountId + '\0' + normalize(cuePath) + '\0' + trackIndex)` |
| CUE 专辑 `cue_id` | `sha1('cue' + '\0' + accountId + '\0' + normalize(cuePath))` |

- **不是**音频字节的内容哈希：换文件、重下、清缓存都不改身份。
- `normalizeRemotePath`：统一 `/`、去重斜杠、保证以 `/` 开头。
- 缓存文件名短茎 = `music_id` 前 16 位（`identityHashStem`）。
- 遗留歌单键仍可用 `trackIdentityKey(accountId, remotePath)`，新逻辑一律优先 `musicId`。

**曲目身份 = 网盘名 + remote_path**。曲库行、云端清单里**不含** URL / 用户名 / 密码，只有 `source_name`；`网盘名 → url / 用户名 / 密码` 只由本机 `accounts` 表解析（`AccountsService.accountForSource` / `idForSource` / `nameForAccount`）。所以把网盘改名会让旧行变成「来源网盘未绑定」（见 [03](03-MUSIC-LIBRARY.md)），改回来即恢复。

## 2. 本地数据库 `music_library.db`（schema v9）

| 表 | 含义 |
|----|------|
| `accounts` | WebDAV / 云盘账号（id / name / url / username / provider_type / remote_path / capabilities）；密码在 secure storage |
| `tracks` | 普通曲目标签；PK = `music_id`，`UNIQUE(source_name, remote_path)` |
| `cue_albums` | CUE 专辑身份（含 `cache_group_id`） |
| `cue_slices` | 虚拟分片（clip 起止、audio_music_id、cache_group_id） |
| `cache_groups` | **运行态**：CUE 缓存组 `group_id → members`（JSON 身份数组，v8 从 prefs 迁入） |
| `cache_access` | **运行态**：LRU 播放时间戳 `(source_name, remote_path) → accessed_at`（v8 从 prefs 迁入） |
| `deleted_tracks` | 删除记录（不做软删列） |
| `sync_state` | 同步游标 |

v9 删除了 `cache` annex 表：它的每一列都没有承载不可推导的信息——`local_path` 恒等于由身份推导出的缓存文件名（`CacheService.fileForRemote`），`etag` / `size_bytes` 从无读取方。**「已缓存」不再是一张表，而是对推导路径的一次惰性 `File.exists`**（见 §3）。

- `tracks` / `cue_*` 用 `source_name` + `rev`；删除走独立表。
- **没有渐进 migration**：`onUpgrade` 直接 DROP 重建，改 schema 就 bump `LibraryDatabase.schemaVersion`。唯一例外是 **v7→v8 的 prefs 迁移**：`cache_group_members_*` 的成员表能从值里还原（`cache_group_codec.dart`），迁完删旧键；`cache_access_*` 的键是 `hashCode`、不可逆，直接删除，过期清理回落到文件 mtime。
- 「CUE 整专辑一组」的**每行归属**仍由 `cue_albums.cache_group_id` / `cue_slices.cache_group_id` / `download_tasks.cache_group_id` 承担；`cache_groups` 只存**成员清单**（组 → 哪些文件），删除组 = 删成员文件 + 删这一行（`CacheService.deleteCacheGroup`）。
- `cache_groups` / `cache_access` 是运行态缓存数据：随 `clearAllLibraryData()` 一起清、随 `clearLibraryIndex()` 一起留；**不进**备份与云端分片。
- 其它库：`download_queue.db`（下载任务）、`playlists.db`（本地歌单）。封面缩略图在应用文档目录 `covers/`，音频在缓存目录。

## 3. 什么算「已缓存」

- **曲库行**（标签 / 封面路径 / CUE clip）与音频文件解耦：清空音频后这些行仍在。
- **可播条件**（v9 起）：由 `(source_name, remote_path)` 推导出的缓存文件路径上 `File.exists`。**没有 annex 表、没有启动对账**——文件在就是已缓存，文件不在就是未缓存，状态不可能 stale（v8 之前需「表有行 且 文件在」双条件并对账清理，v9 起单条件即可）。
- **不要**信任「曾经 completed」的队列状态；推导路径是唯一事实源。
- 缓存文件名 = `identityHashStem(网盘, 路径) 前 16 位 _ 净化后的原文件名`，纯函数、跨设备一致（16 hex = 64 bit，万首量级碰撞概率 ~10⁻¹²，且还需文件名相同才真撞）。
- 两种删除的语义完全不同：

| 操作 | 入口 | 删除 | 保留 |
|------|------|------|------|
| 清空音频缓存 | 设置（也按天 / 周自动清理） | `music_cache/` 下音频文件（保护正在播放 / 下载的） | tracks / cue / covers / 账号 / 歌单 |
| 删除缓存（单条或整组） | 音乐库 / 网络库多选 | 该条（或该 CUE 组）的音频文件 | 标签、封面、歌单引用 |
| **销毁音乐库 / 销毁曲目** | 音乐库菜单「销毁」 | 标签、cue 表、封面、对应音频文件；歌单去掉失效引用 | 网络库与账号；歌单壳可留空 |

- 销毁路径不再触碰任何缓存状态表（v9 起没有要清的表）；`markAllUncached()` 保留为 no-op 以兼容备份恢复调用点。
- 设置清空缓存后，队列里那些「文件已不存在」的缓存任务行会被**删除**（相册 / 下载目录任务跳过），于是曲目回到「未下载」而不是「错误」——细节见 [04](04-DOWNLOAD-QUEUE.md)。

## 4. 云端文件的语义约定

总路径（网盘 + 路径）与派生规则见 [08 §1](08-SYNC-AND-BACKUP.md)。在总路径之下，文件名的含义是固定的：

| 文件 / 目录 | 语义 |
|-------------|------|
| `credentials.json` | WebDAV 账号表；**地址与用户名明文，只有密码加密**（`AESGCMv1:`） |
| `playlists/*.m3u8` | 歌单，一份一个文件；`updatedAt` 最后写入胜出 |
| `library/index.json` | 曲库清单：分片文件名 / 片数 / 字节数 / rev 区间 |
| `library/lib-*.wdmm` | 基础分片（重建产出） |
| `library/seg-*.wdmm` | 增量分片（每次同步追加） |
| `library/del-*.wdmm` | 墓碑分片（删除记录，重建时才真正落实） |
| `backup/backup-<UTC>.wdmm`、`backup/webdav_media_backup.wdmm` | 整机备份归档（凭证 + 曲库 + 歌单 + 封面 + 设置） |

分片里**没有**网盘地址 / 用户名 / 密码，只有 `source_name`。

## 5. 二进制容器与魔数

所有二进制文件（云端分片、备份、加密信封）都是同一个容器：8 字节头 `'WDMM'` + 2 字符种类 + 2 位布局版本 + `u16 sectionCount` + `u16 flags`（预留）+ section 表 + 每 section CRC32（`lib/utils/wmp_container.dart`）。**种类可从前 8 字节直读**，不需要解压；未知种类 / 版本按名字报错，因此新旧布局能和平共存。

| 魔数 | 种类 | 用途 |
|------|------|------|
| `WDMMLB01` | `LB` | 云端库基础分片 `lib-*.wdmm` |
| `WDMMLS01` | `LS` | 云端库增量分片 `seg-*.wdmm` |
| `WDMMLT01` | `LT` | 云端库墓碑 `del-*.wdmm` |
| `WDMMBK01` | `BK` | 备份归档 |
| `WDMMEN01` | `EN` | 口令加密信封（AES-256-GCM + PBKDF2），解密后才是上面某种文件或 JSON |
| `WDMMEX01` | `EX` | 预留：分享用曲库文件 |
| `WDMMCR01` | `CR` | 预留：凭证二进制包 |

新增种类 = `WmpFileKind` 加一行 + `WmpKind` 加对应数字（`metaKindOf` / `forMetaKind` 互相映射）；解析时交叉校验「魔数种类」与「META.kind」。

## 6. 版本时钟 `rev`

`lib/utils/rev_clock.dart`：`rev = max(nowMs, last + 1)`，严格单增、时钟回拨不回退；`compareRev` 在 rev 相同时用 `deviceId` 决胜。跨设备合并（曲库清单、歌单、墓碑）都按 rev 判定谁更新。
