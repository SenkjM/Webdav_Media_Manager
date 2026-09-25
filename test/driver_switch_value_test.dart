// 开关字段取值联动回归（99 §7.2.10）。
//
// 背景 bug：账号配置界面里「在本地处理令牌刷新」这类开关的联动不对——开关
// 自身显示、被联动字段的显示/可编辑性、以及保存下来的值三者会互相打架，
// 且出现「回退」。根因是取值规则在不同路径上不一致：
//   - 渲染 / 联动路径写死 `?? false`
//   - 初始化与保存路径用 `?? item.defaultValue`
// 于是「默认开」的开关在 values 缺键时会被当成关。
//
// 现在渲染、联动、保存统一走 CloudDriverSpec.switchValue，本文件锁死该语义。
// 另锁死百度本地刷新开关的**联动极性**（99 §7.3.1）：关闭＝在线续期地址可用
// （走 online api），打开＝地址停用 + Client ID / Secret 显示（自建应用刷新）。

import 'package:flutter_test/flutter_test.dart';

import 'package:webdav_media_manager/services/cloud_driver.dart';
import 'package:webdav_media_manager/services/cloud_drivers/baidu_netdisk_driver.dart';

/// 合成 spec：一个默认开、一个默认关的开关，用于验证两条分支。
class _SwitchSpec extends CloudDriverSpec {
  const _SwitchSpec();

  @override
  String get typeId => 'switch_spec';

  @override
  String get displayName => '开关测试';

  @override
  int get capabilities => 0;

  @override
  List<CloudDriverFormItem> get form => const [
        CloudDriverSwitchField(
          key: 'on_by_default',
          label: '默认开',
          subtitle: '',
          defaultValue: true,
        ),
        CloudDriverSwitchField(
          key: 'off_by_default',
          label: '默认关',
          subtitle: '',
        ),
      ];

  @override
  CloudDriver create(
    Map<String, dynamic> config, {
    void Function(Map<String, dynamic> patch)? onTokenUpdate,
    CloudDriverEnv? env,
  }) =>
      throw UnimplementedError();
}

/// 复刻 accounts_screen 渲染层的双极性判定，锁定「界面实际行为」。
/// enabledWhenSwitch = 开了才可用；disabledWhenSwitch = 开了就停用。
/// 两者同声明视为无依赖（防误用，渲染层同一规则）。
bool _fieldEnabled(
  CloudDriverSpec spec,
  String key,
  Map<String, bool> values,
) {
  final f = spec.form
      .whereType<CloudDriverField>()
      .firstWhere((f) => f.key == key);
  final dependsEnabled =
      f.enabledWhenSwitch != null && f.disabledWhenSwitch == null;
  final dependsDisabled =
      f.disabledWhenSwitch != null && f.enabledWhenSwitch == null;
  if (dependsDisabled) {
    return !spec.switchValue(f.disabledWhenSwitch!, values);
  }
  if (dependsEnabled) {
    return spec.switchValue(f.enabledWhenSwitch!, values);
  }
  return true;
}

bool _fieldVisible(
  CloudDriverSpec spec,
  String key,
  Map<String, bool> values,
) {
  final f = spec.form
      .whereType<CloudDriverField>()
      .firstWhere((f) => f.key == key);
  if (f.visibleWhenSwitch == null) return true;
  return spec.switchValue(f.visibleWhenSwitch!, values);
}

void main() {
  group('CloudDriverSpec.switchValue', () {
    test('实时值优先于 spec 默认值', () {
      const spec = _SwitchSpec();
      // 默认开的开关被用户拨到关：必须读到关，不能回落到默认值。
      expect(spec.switchValue('on_by_default', {'on_by_default': false}),
          isFalse);
      // 默认关的开关被拨到开。
      expect(spec.switchValue('off_by_default', {'off_by_default': true}),
          isTrue);
    });

    test('缺键时回落到 spec 默认值，而不是 false', () {
      const spec = _SwitchSpec();
      // 这是 bug 的核心断言：缺键 + 默认开 → 开。
      expect(spec.switchValue('on_by_default', const {}), isTrue);
      expect(spec.switchValue('off_by_default', const {}), isFalse);
    });

    test('只缺被依赖的那个键时，其余键仍然按实时值走', () {
      const spec = _SwitchSpec();
      final values = {'off_by_default': true};
      expect(spec.switchValue('off_by_default', values), isTrue);
      expect(spec.switchValue('on_by_default', values), isTrue);
    });

    test('未声明的 key 返回 false', () {
      const spec = _SwitchSpec();
      expect(spec.switchValue('nope', const {}), isFalse);
      expect(spec.switchValue('nope', {'nope': true}), isTrue);
    });
  });

  group('百度网盘 spec 联动字段', () {
    const spec = BaiduNetdiskSpec();

    test('local_refresh 默认关：Client ID / Secret 隐藏，续期地址可编辑', () {
      const values = <String, bool>{};
      expect(spec.switchValue('local_refresh', values), isFalse);

      // 依赖描述与 spec 声明一致，防止改名后联动悄悄失效。
      final fields = spec.form.whereType<CloudDriverField>().toList();
      final cid = fields.firstWhere((f) => f.key == 'client_id');
      final secret = fields.firstWhere((f) => f.key == 'client_secret');
      final api = fields.firstWhere((f) => f.key == 'api_url_address');

      expect(cid.visibleWhenSwitch, 'local_refresh');
      expect(secret.visibleWhenSwitch, 'local_refresh');
      // 99 §7.3.1：开关打开（本地刷新）才停用 online api 地址——
      // 「开了就停用」，不是「开了才可用」。
      expect(api.disabledWhenSwitch, 'local_refresh');
      expect(api.enabledWhenSwitch, isNull);
    });

    test('user 打开 local_refresh 后联动翻转', () {
      const values = {'local_refresh': true};
      expect(spec.switchValue('local_refresh', values), isTrue);
    });

    test('联动极性：关闭＝续期地址可用，打开＝地址停用（99 §7.3.1）', () {
      // 开关关闭（false）→ 在线续期地址必须可编辑（正在用 online api）。
      expect(_fieldEnabled(spec, 'api_url_address', const {}), isTrue);
      // 开关打开（true）→ 地址停用（后端已不走 online api）。
      expect(_fieldEnabled(spec, 'api_url_address',
          const {'local_refresh': true}), isFalse);
      // Client ID / Secret 只在开关打开时显示。
      expect(_fieldVisible(spec, 'client_id', const {}), isFalse);
      expect(_fieldVisible(spec, 'client_id',
          const {'local_refresh': true}), isTrue);
    });

    test('联动引用的开关确实存在于 form 里（防拼写错导致永远 false）', () {
      final switchKeys = spec.form
          .whereType<CloudDriverSwitchField>()
          .map((s) => s.key)
          .toSet();
      for (final f in spec.form.whereType<CloudDriverField>()) {
        if (f.visibleWhenSwitch != null) {
          expect(switchKeys, contains(f.visibleWhenSwitch),
              reason: 'visibleWhenSwitch 指向了不存在的开关');
        }
        if (f.enabledWhenSwitch != null) {
          expect(switchKeys, contains(f.enabledWhenSwitch),
              reason: 'enabledWhenSwitch 指向了不存在的开关');
        }
        if (f.disabledWhenSwitch != null) {
          expect(switchKeys, contains(f.disabledWhenSwitch),
              reason: 'disabledWhenSwitch 指向了不存在的开关');
        }
      }
    });
  });
}
