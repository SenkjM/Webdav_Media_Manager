// 驱动注册表（对齐 OpenList 的 bootstrap/drivers 注册点，99 §7.2.10）。
//
// 驱动实现在 Rust（wdmm-core）。这里只保留表单元数据（WdmmVfsSpec 子类），
// 供账号表单渲染用。新增一个网盘 = 新增 provider_specs.dart 里的一个 spec
// 类 + 在 kWdmmVfsSpecs 加一行；账号表单与兼容层零改动。crypt 永远最后。

import '../wdmm_vfs.dart';

import 'provider_specs.dart';

/// 已落地的驱动；顺序即账号表单类型下拉的显示顺序。
/// crypt 永远最后（包装层）；netease_music 是并行任务收编进来的，放最后一位
/// 独立驱动（用户决定），其余按落地时间序。
const List<WdmmVfsSpec> kWdmmVfsSpecs = <WdmmVfsSpec>[
  BaiduNetdiskSpec(),
  Driver123OpenSpec(),
  Open115Spec(),
  AliyundriveOpenSpec(),
  TeraboxSpec(),
  NeteaseMusicSpec(),
  CtFileSpec(),
  CryptSpec(),
];

/// 按存库的 provider_type 查驱动描述符；未注册返回 null。
WdmmVfsSpec? wdmmVfsSpec(String typeId) {
  for (final spec in kWdmmVfsSpecs) {
    if (spec.typeId == typeId) return spec;
  }
  return null;
}
