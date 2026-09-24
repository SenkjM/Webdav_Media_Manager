// 驱动注册表（对齐 OpenList 的 bootstrap/drivers 注册点，99 §7.2.10）。
//
// 新增一个网盘 = 新增驱动文件（驱动 + Addition + 能力遮罩 + 表单参数
// 全在里头）+ 在 kCloudDriverSpecs 加一行；账号表单与兼容层零改动。
// crypt 这类中间处理层落地时同样在这里注册：spec.create() 包住内层驱动。

import '../cloud_driver.dart';

import 'baidu_netdisk_driver.dart';

/// 已落地的驱动；顺序即账号表单类型下拉的显示顺序。
const List<CloudDriverSpec> kCloudDriverSpecs = <CloudDriverSpec>[
  BaiduNetdiskSpec(),
];

/// 按存库的 provider_type 查驱动描述符；未注册返回 null。
CloudDriverSpec? cloudDriverSpec(String typeId) {
  for (final spec in kCloudDriverSpecs) {
    if (spec.typeId == typeId) return spec;
  }
  return null;
}
