# D02 · 后台下载与文件动作

> **本文件是当前唯一活跃计划，不是已实现功能。**  
> Agents：除非用户明确要求实现某一块，否则只读本文件做规划；不要把下列条目当作已支持能力。

> **文档编号 D02** · 状态：进行中 · 模式：活跃  
> 总索引：[INDEX.md](../INDEX.md)

相关保留文档：

- 产品概览与路线图概览：[README.md](../../README.md)
- 构建与编码约定（归档）：[A05-BUILD-AND-CONVENTIONS.md](../archive/A05-BUILD-AND-CONVENTIONS.md)
- 真机验证（归档）：[A06-DEVICE-QA-CHECKLIST.md](../archive/A06-DEVICE-QA-CHECKLIST.md)
- 已完成的视频/同步大改（归档只读）：[A01-CHANGE-PLAN-video-sync.md](../archive/A01-CHANGE-PLAN-video-sync.md)

---

## 1. 原则

1. **先修后台下载**（P0）：切后台后音乐下载 `fail host lookup` 单独优先，不与文件动作重构绑在一起。
2. **文件选择 / 多选重构一次做透**（P1）：把长期「四种动作」设计与「普通文件多选下载不可用」一并修掉；拆成可独立验收的分块任务（T1–T6），按依赖顺序推进。
3. 用户预期：P1 重构完成后，**除后台下载外**的当前已知下载/多选问题应一并消失。
4. 本文件只记录计划与验收；实现时另开提交，按块验收，不要在文档提交里改业务代码。

---

## 2. 总览表

| 优先级 | 块 | 说明 | 验收（摘要） |
|---|---|---|---|
| **P0** | 后台下载 | 切后台/锁屏后音乐下载报 `fail host lookup` | 后台仍能下完；日志无 host lookup |
| **P1-T1** | 统一文件动作模型 | `stream` / `cache` / `cache-then-play` / `download`；设置按后缀配单击 | 模型与设置 UI 一致；单测覆盖分类与默认 |
| **P1-T2** | 下载至指定文件夹 | 默认系统下载；普通文件默认「下载」 | 普通文件落到 Downloads（或用户指定目录） |
| **P1-T3** | 多选工具栏四动作 | 缓存类按音乐后缀过滤 + 弹窗 | 四按钮可用；非音乐被过滤并提示 |
| **P1-T4** | 单文件「更多」菜单 | 串流/下载全文件；缓存类仅音乐 | 非音乐无缓存动作（隐藏或置灰） |
| **P1-T5** | 修普通文件多选下载 | 与 T2/T3 合并验收 | 多选普通文件可下到文件夹（视频路径保持） |
| **P1-T6** | （可选）音频串流 | 复用视频播放逻辑 | 音频可 stream；不阻塞 T1–T5 |
| **P2+** | 路线图剩余项 | 国产 ROM 通知、视频 QA 未做项等 | 见 README / DEVICE-QA；本文不展开 |

---

## 3. P0 — 后台下载 `fail host lookup`（单独优先）

### 现象

- 应用切到后台（或锁屏）后，**音乐下载失败**。
- 错误特征：日志 / Snack 出现 **`fail host lookup`**（DNS 解析失败类）。
- 前台下载通常正常；问题与生命周期 / 后台网络策略强相关。

### 调查方向（假设，均待验证）

| # | 假设 | 建议验证 |
|---|---|---|
| H1 | 系统在后台限制 DNS / 网络（Doze、应用待机、ColorOS 后台联网策略） | 复现时抓 `logcat`；对比前台/后台；检查电池优化白名单 |
| H2 | WebDAV client（HTTP 连接）在 `AppLifecycleState.paused` 后未重建，复用失效连接 | 在 pause/resume 打断点；检查 `WebDavService` 是否需 reconnect |
| H3 | 缺少 **foreground service** 专用于下载（仅有媒体通知不足以保活网络） | 对照 Android 后台限制；评估下载专用 FGS + 类型声明 |
| H4 | ColorOS / 一加等国产 ROM 额外杀后台网络 | 真机复现；对照 [真机验证清单](../archive/A06-DEVICE-QA-CHECKLIST.md) 国产 ROM 项 |

### 主要触及（实现时）

- `lib/services/download_queue_service.dart` — 队列执行与错误面
- `lib/services/webdav_service.dart` — `downloadToFile` / 连接生命周期
- `lib/services/download_notification_service.dart` / `media_notification_channel.dart` — 通知与保活边界
- `lib/utils/android_background.dart`、`AndroidManifest` / 原生侧 FGS（若采用）
- `lib/main.dart` / `lib/providers/app_state.dart` — 生命周期挂钩

### 验收

- [ ] 开始下载后立刻 Home / 锁屏，任务仍能完成并正确 ingest（音乐进缓存 / 库）。
- [ ] 同场景日志中 **不再出现** `fail host lookup`（或等价 DNS 失败）。
- [ ] 前台下载回归无回退；取消 / 重试仍可用。
- [ ] 在至少一台目标国产 ROM（若可获取）上复验。

**依赖**：无；可先于全部 P1 独立合入。

---

## 4. P1 — 文件选择 / 多选重构（分块任务）

### 当前 Bug 澄清（须一并解决）

- **不是**「多选下载完全失效」。
- **视频**多选下载可以下到文件夹（系统相册路径，`enqueueGalleryMany`）。
- **普通文件**（非音乐、非视频，即未知后缀 / `FileCategory.other`）多选下载**不行**。
- 根因线索（实现时验证）：`network_library_screen.dart` 的 `_enqueueMany` 对非视频走 `ensureQueued`，且 **`if (!item.isAudio) continue;`**，直接跳过普通文件；而单击未知后缀走 `_enqueueUnknown` → `enqueueToDownloads`。重构后应用统一「下载」动作覆盖该路径。

用户预期：完成本节重构后，**除 P0 后台下载外**，当前已知的下载 / 多选相关问题应修复。

### 四种动作（长期设计，并入本轮）

| 动作 | 语义 |
|---|---|
| **流式播放**（stream） | 远端直接播，不先落完整本地缓存 |
| **缓存**（cache） | 写入应用缓存，完成后不自动播放 |
| **缓存后播放**（cache-then-play） | 先缓存，完成后再用本地文件播放 |
| **下载**（download） | 下载到用户指定文件夹；未指定则用系统下载目录 |

### T1 — 统一文件动作模型与设置单击

- **目标**：定义统一动作枚举 / 配置；设置里可按**后缀**（或文件类）选择单击行为（四选一）；与现有 `MusicTapAction` / `VideoTapAction` 收敛或适配层过渡。
- **主要触及**：
  - `lib/models/file_type_config.dart`
  - `lib/services/settings_service.dart`
  - `lib/screens/settings_screen.dart`、`lib/screens/file_extensions_screen.dart`
  - `lib/screens/network_library_screen.dart`（`_onTapFile`）
  - `lib/providers/app_state.dart`（若注入分类器）
- **验收**：
  - [ ] 四种动作在模型层可表达；设置可读写且持久化。
  - [ ] 单击按当前后缀配置执行对应动作（至少在测试或可观测日志中可区分）。
  - [ ] 默认值文档化：普通文件默认见 T2。
- **依赖**：无（可先落地模型 + 设置，UI 可暂映射到旧行为）。

### T2 — 下载至指定文件夹；普通文件默认「下载」

- **目标**：`download` 动作写入用户指定目录（默认系统 Downloads）；普通文件（非音乐 / 非视频）单击默认「下载」（不是进音乐缓存）。
- **主要触及**：
  - `lib/services/download_queue_service.dart`（`enqueueToDownloads` 等）
  - `lib/services/platform_export_service.dart`（`saveToDownloads` / SAF 选目录若需要）
  - `lib/screens/network_library_screen.dart`（`_enqueueUnknown`、`_enqueueOnly`）
  - 设置项：默认下载目录（若本轮做可选目录选择）
- **验收**：
  - [ ] 单文件「下载」落到系统下载（或用户选定目录），不进音乐库索引。
  - [ ] 普通文件默认单击 = 下载；视频相册路径、音乐缓存路径不回归。
- **依赖**：T1（动作语义）；可与 T5 合并联调。

### T3 — 多选工具栏四种动作

- **目标**：长按进入多选后，工具栏提供全部四种动作。
  - 流式播放、下载：可作用于所选全部文件。
  - 缓存、缓存后播放：执行前按**音乐后缀**过滤；非音乐过滤掉并**弹窗**说明；剩余音乐继续执行。
- **主要触及**：
  - `lib/screens/network_library_screen.dart`（`_buildSelectionBar`、`_enqueueMany`、选中态）
  - `lib/services/download_queue_service.dart`（批量 enqueue）
  - 播放入口：`video_playback_service` / `audio_player_service`（stream 批量策略需明确：逐个开播或只播第一个 + 入队）
- **验收**：
  - [ ] 工具栏可见四动作；下载批量对视频 / 音乐 / 普通文件路径正确分流。
  - [ ] 对混合选择点「缓存」：弹窗提示过滤，仅音乐入队。
- **依赖**：T1、T2；与 T5 合并验收普通文件下载。

### T4 — 单文件右侧「更多」

- **目标**：
  - 流式播放、下载：所有文件可用。
  - 缓存、缓存后播放：仅音乐后缀（非音乐隐藏或置灰，不可绕过）。
- **主要触及**：
  - `lib/screens/network_library_screen.dart`（`_showItemMenu` / 更多菜单）
- **验收**：
  - [ ] 非音乐「更多」仅串流 + 下载可执行。
  - [ ] 音乐四动作齐全且行为与设置单击一致。
- **依赖**：T1、T2。

### T5 — 修普通文件多选下载路径（与 T2/T3 合并验收）

- **目标**：消除 `_enqueueMany` 跳过非音频的缺陷；多选「下载」对普通文件走与 T2 相同的 `download` / `enqueueToDownloads` 路径；视频保持相册（或统一到「下载」配置若产品决定——默认保持现有视频→相册，除非设置覆盖）。
- **主要触及**：同 T2/T3；重点改 `network_library_screen.dart` `_enqueueMany`。
- **验收**：
  - [ ] 仅选普通文件 → 多选下载成功，文件出现在系统下载（或指定目录）。
  - [ ] 混合选视频 + 普通文件 + 音乐 → 各走正确落盘；Snack / 队列状态正确。
  - [ ] 回归：仅视频多选仍进系统相册（若未改产品规则）。
- **依赖**：T2、T3（建议同一 PR 或紧邻 PR 合并验收）。

### T6 —（可选 / 更后）音频串流复用视频播放逻辑

- **目标**：音频 `stream` 动作复用视频侧已有的远端流式打开逻辑（`WebDavService.buildStreamSource`、播放器栈），避免另起一套。
- **主要触及**：
  - `lib/services/video_playback_service.dart` / `webdav_service.dart`
  - `lib/screens/video_player_screen.dart` 或音频播放路径适配
  - `lib/services/audio_player_service.dart`、`music_audio_handler.dart`
- **验收**：
  - [ ] 音频可配置为串流并实际播放；切歌 / 通知行为有明确产品结论。
  - [ ] 不破坏「先缓存再播」默认路径。
- **依赖**：T1；**不阻塞** T2–T5。可放到 P1 收尾或 P2。

---

## 5. 不在本计划内

路线图其余方向已按主题冻结在[产品路线图](../archive/A07-PRODUCT-ROADMAP.md)，不在本计划展开，也不要当作当前范围。

---

## 6. Agents 工作约定

1. 实现前先读本文件对应块的「目标 / 触及 / 验收 / 依赖」。
2. 一次 PR 尽量对应一块（或 T2+T3+T5 合并验收组）；提交说明写清块 ID。
3. 不要在「仅文档」任务里改 `lib/`；不要实现未点名的 P2+。
4. 若发现本文件与代码严重脱节，先改文档再改代码，或在同一需求下同步更新本文件。
