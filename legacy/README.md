# 云盘驱动作废档案（已作废 · 重写参考）

> **状态声明**：本目录下的整批云盘驱动实现（`lib/services/cloud_driver.dart` 基类、
> `lib/services/cloud_drivers/` 下 6 个驱动、`driver_registry.dart` 注册表及
> stream_bridge / webdav_source 支撑层）已按维护者决定**作废、待重写**。重写完成前
> 代码仍在仓库中运行，但其实现不再维护、不接收功能增强。
>
> 本目录是这批实现的**功能性档案**：逐驱动记录能力位、表单字段、认证与令牌生命
> 周期、接口逐条行为、直链与请求头、特殊机制与取舍、测试契约与重写陷阱，供重写
> 时对照。全部事实来自当前源码（含文件头与行内注释），未掺杂臆测。
>
> **来源与版权声明**：本目录各文档为独立整理的功能性规格，仅描述本项目自有实现的
> 可观察行为与接口契约；**不参考、不引用、不包含来自 OpenList / OpenList-Worker 的
> 任何源码或其衍生内容**。
>
> crypt 驱动已通过外部包与调用实现版权隔离，不在本目录重写范围内，其档案文档已移除。
>
> 本目录独立于 `docs/` 编号体系（维护者豁免），不进 00-INDEX 索引。

## 目录内容

| 文档 | typeId / displayName | 能力位 | 备注 |
|---|---|---|---|
| [baidu_netdisk.md](baidu_netdisk.md) | `baidu_netdisk` / 百度网盘 | list·read·mkdir·move·copy·delete | 5 表单字段；dlink→HEAD 302→`_sanitizeDlink` 消毒；UA `pan.baidu.com` |
| [123_open.md](123_open.md) | `123_open` / 123云盘 | list·read·mkdir·move·delete（无 copy） | copy 为同步抛错桩（无可用实现）；`local_refresh` 反相开关 |
| [115open.md](115open.md) | `115open` / 115网盘 | list·read·mkdir·move·copy·delete | 双 base（proapi / passportapi）；直链带 UA；30 分钟链接缓存 |
| [aliyundrive_open.md](aliyundrive_open.md) | `aliyundrive_open` / 阿里云盘开放 | list·read·mkdir·move·copy·delete | 8 表单字段（隐式 drive_id 不进表单）；在线续期 6 内置候选轮询 |
| [terabox.md](terabox.md) | `terabox` / TeraBox | list·read·mkdir·move·copy·delete | RC4 式签名（KSA+PRGA 异或+base64，非 MD5）；jsToken 进程内刷新 |
| [netease_music.md](netease_music.md) | `netease_music` / 网易云音乐 | list·read·delete | cookie 认证；weapi 双层 AES-CBC + RSA encSecKey；平铺无目录树 |
| [infrastructure.md](infrastructure.md) | ——（支撑层） | —— | `CloudDriver` 基类契约、`CloudDriverSpec` 表单/自描述、注册表、MustProxy 本地流桥、WebDAV 源适配、共享测试 |

统一能力模型：`AccountCaps` 位定义（`lib/models/account_capabilities.dart`），
`list`(1<<0) / `read`(1<<1) / `write`(1<<2) / `mkdir`(1<<3) / `move`(1<<4) /
`copy`(1<<5) / `delete`(1<<6)。**全批均无 write 位**——上传在 99 §4.2.1 全局砍掉。

## 文档骨架

六份驱动文档统一 9 章：1 标识 / 2 能力位 / 3 表单字段 / 4 认证与令牌生命周期 /
5 接口实现逐条 / 6 直链与请求头 / 7 特殊机制与取舍 / 8 行为契约（重写必须保持的
契约）/ 9 重写注意事项（从实现提炼的陷阱）。infrastructure.md 为 11 章变体
（按支撑组件分章：基类契约 / 数据与异常 / 路径工具 / 表单系统 / spec 自描述 /
包装机制 / 注册表 / 本地流桥 / WebDAV 源 / 共享测试 / 陷阱）。

各文档为独立整理的功能性规格，不引用任何外部项目的源码。

## 重写入口建议

1. **先读 [infrastructure.md](infrastructure.md)**——基类契约（`CloudDriver` /
   `CloudDriverSpec` / `CloudSource` / 表单系统）与注册表是所有驱动的公共面；
   §11 记录了支撑层已知问题（如 `driver_secret_scope_test.dart` 的 audited 集合
   与注释键数不一致，断言只查单向包含）。
2. **再按注册表顺序读各驱动**（`kCloudDriverSpecs`：baidu → 123 → 115 →
   aliyundrive → terabox → netease）。§8 行为契约是重写必须保持的
   行为契约（含数字级断言，如 terabox 金标向量
   `teraboxSign('sign3key','sign1data') == 'RF9iI+bxb964'`）。
3. 各驱动 §9 陷阱清单是重写时的第一张检查表（如 terabox 的「任务背景称 MD5
   签名」勘误、baidu 的令牌错误刷新后仍抛错不重试）。

## 关联文档（docs/，已同步改为功能性表述）

- [docs/11-CLOUD-DRIVER-PORTING.md](../docs/11-CLOUD-DRIVER-PORTING.md)——驱动实现要点与陷阱（架构映射、格式对齐、8 大陷阱）。
- [docs/12-DRIVER-PORTING-GUIDE.md](../docs/12-DRIVER-PORTING-GUIDE.md)——驱动接入指南（解耦边界、固定六步工序、验收清单）。
- [docs/13-DRIVER-BATCH-PLAN.md](../docs/13-DRIVER-BATCH-PLAN.md)——能力核查与接入批次记录。
