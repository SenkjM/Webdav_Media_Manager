# 文档总索引（编号体系）

面向人类开发者与 coding agents。**实现功能前先读本索引，再读状态为「进行中」的计划。**

## Agents 规则（硬约束）

1. **先读索引**：动手前打开本文件，确认当前「进行中」文档。
2. **归档**：模式为「归档」的文档正文，更改相关代码需要得到用户许可，再进行更变。
3. **新发文档**：取下一个可用编号（活跃用 `D##`，归档用 `A##`），写入本表。计划类放 `active/`，状态「进行中」、模式「活跃」。
4. **完成归档**：本表将该条标为「已完成」+ 模式「归档」→ 文件移入 `archive/` → 更新路径；此后正文保持稳定。
5. **活跃目录只放当前计划**。参考说明、清单、路线图归档后只读，不要在 `active/` 再堆平行长文。
6. **入口**：本仓库文档以本索引为唯一入口。
7. **分支设定**: main分支只有用户明确允许才可以合并。beta分支可以作为一般工作保存使用，agent判断在当前任务完成后可以可以提交至云端。dev分支则是在进行重大破坏性更改时使用，主要为历史遗留，更推荐基于beta独立功能分支进行测试。

| 状态 | 含义 |
|------|------|
| `进行中` | 未完成，且允许按本表推进 |
| `已完成` | 已移入归档。规划类的「已完成」表示快照冻结，不表示功能已实现 |

| 模式 | 含义 |
|------|------|
| `活跃` | 根据代码状况自行调整 |
| `归档` | 需得到用户许可后修改 |

---

## 索引表

| 编号 | 标题 | 状态 | 模式 | 路径 | 备注 |
|------|------|------|------|------|------|
| D02 | 后台下载与文件动作 | 进行中 | 活跃 | [active/D02-BACKGROUND-DOWNLOAD-AND-FILE-ACTIONS.md](active/D02-BACKGROUND-DOWNLOAD-AND-FILE-ACTIONS.md) | 唯一活跃计划 |
| A01 | 视频、相册、通知与同步备份 | 已完成 | 归档 | [archive/A01-CHANGE-PLAN-video-sync.md](archive/A01-CHANGE-PLAN-video-sync.md) | 已落地的变更记录 |
| A02 | 架构与数据模型 | 已完成 | 归档 | [archive/A02-ARCHITECTURE-AND-DATA.md](archive/A02-ARCHITECTURE-AND-DATA.md) | 原开发文档拆分 |
| A03 | 播放与曲库行为 | 已完成 | 归档 | [archive/A03-PLAYBACK-AND-LIBRARY.md](archive/A03-PLAYBACK-AND-LIBRARY.md) | 原开发文档拆分 |
| A04 | 同步与备份 | 已完成 | 归档 | [archive/A04-SYNC-AND-BACKUP.md](archive/A04-SYNC-AND-BACKUP.md) | 原开发文档拆分 |
| A05 | 构建、发布与编码约定 | 已完成 | 归档 | [archive/A05-BUILD-AND-CONVENTIONS.md](archive/A05-BUILD-AND-CONVENTIONS.md) | 原开发文档拆分 |
| A06 | 真机验证清单 | 已完成 | 归档 | [archive/A06-DEVICE-QA-CHECKLIST.md](archive/A06-DEVICE-QA-CHECKLIST.md) | 勾选状态已冻结 |
| A07 | 产品路线图 | 已完成 | 归档 | [archive/A07-PRODUCT-ROADMAP.md](archive/A07-PRODUCT-ROADMAP.md) | 规划快照，不是已实现功能 |

---

## 目录约定

```
docs/
  INDEX.md                 # 本文件
  active/                  # 当前计划（D##）
  archive/                 # 归档（A##，只读）
```

下一活跃编号：`D03`。下一归档编号：`A08`。
