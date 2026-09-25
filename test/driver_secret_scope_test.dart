import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/services/cloud_drivers/driver_registry.dart';

/// 凭证同步/备份的**加密范围**规则（08 §2）：
/// secretFieldKeys = 表单 obscure 字段（「配置界面默认为密码的数据」）
/// ∪ runtimeSecretKeys（运行时 onTokenUpdate 写回的令牌缓存键）。
///
/// 新驱动落地时这里必须补一条实测：加密范围不用手动维护，但**令牌缓存键
/// 是否已声明**要人工确认（表单看不见运行时写回的键）。
void main() {
  group('spec 加密范围（secretFieldKeys）', () {
    test('baidu_netdisk：refresh_token / client_secret（表单）+ access_token（运行时）', () {
      final keys = cloudDriverSpec('baidu_netdisk')!.secretFieldKeys;
      expect(keys, containsAll(['refresh_token', 'client_secret', 'access_token']));
      expect(keys, isNot(contains('api_url_address')));
      expect(keys, isNot(contains('client_id')));
    });

    test('123_open：refresh_token / client_secret（表单）+ access_token（运行时）', () {
      final keys = cloudDriverSpec('123_open')!.secretFieldKeys;
      expect(keys, containsAll(['refresh_token', 'client_secret', 'access_token']));
      expect(keys, isNot(contains('root_folder_id')));
    });

    test('netease_music：仅 cookie（无令牌轮换 → runtimeSecretKeys 为空）', () {
      final spec = cloudDriverSpec('netease_music')!;
      expect(spec.runtimeSecretKeys, isEmpty);
      expect(spec.secretFieldKeys, ['cookie']);
    });

    test('crypt：password / salt（obscure 表单字段）', () {
      final keys = cloudDriverSpec('crypt')!.secretFieldKeys;
      expect(keys, containsAll(['password', 'salt']));
      expect(keys, isNot(contains('source_account_id')));
    });

    test('加密范围只来自 spec 声明：凭证库/备份不需要为每个驱动登记', () {
      // 结构性保证：所有已注册驱动的加密范围都能从 spec 推导出来（非空
      // 集至少含一个键——若某天出现零键驱动，说明它没有凭证也没有令牌，
      // 需要确认这是事实而不是漏声明）。
      for (final spec in kCloudDriverSpecs) {
        expect(
          spec.secretFieldKeys,
          isNotEmpty,
          reason: '${spec.typeId} 的加密范围为空：确认该驱动真的无凭证、'
              '无令牌缓存，否则补 obscure 声明或 runtimeSecretKeys',
        );
      }
    });

    test('隐式键（表单之外写回/读取的配置键）必须定性：密文 → runtimeSecretKeys，非密文 → 表单显式声明或注释说明', () {
      // 11 §6.2：允许隐式键（如运行时令牌缓存、表单写入的派生快照），
      // 但每个隐式键必须落在三类之一。这里是**当前全量清点的锁定断言**：
      // 新驱动 / 新键落地时更新此清单（对照 Addition.fromJson/toJson 与
      // onTokenUpdate 写回的键），漏登记的隐式键会从这条断言的失败里暴露。
      const audited = <String, Set<String>>{
        // baidu：6 键 = 表单 5（refresh_token/api_url_address/local_refresh/
        // client_id/client_secret）+ 隐式 access_token（运行时缓存，密文）。
        'baidu_netdisk': {
          'refresh_token', 'client_secret', 'access_token', // 密文
          'api_url_address', 'client_id', // 非密文，表单声明
        },
        // 123：同构，多 root_folder_id（非密文，表单声明）。
        '123_open': {
          'refresh_token', 'client_secret', 'access_token', // 密文
          'api_url_address', 'client_id', 'root_folder_id', // 非密文
        },
        // netease：2 键全表单；cookie 密文；无令牌轮换。
        'netease_music': {'cookie'},
        // crypt：9 键 = 表单 8 + 隐式 source_account_id_name（表单通用写入
        // 的源账号名快照，非凭证，明文正确）；password/salt 密文。
        'crypt': {'password', 'salt'},
      };
      for (final spec in kCloudDriverSpecs) {
        final declared = audited[spec.typeId];
        expect(
          declared,
          isNotNull,
          reason: '${spec.typeId} 未进隐式键清点：对照 11 §6.2 补齐',
        );
        // 密文集合必须是清点集合的子集（加密范围 ⊆ 全部定性过的键）。
        expect(
          spec.secretFieldKeys.difference(declared!),
          isEmpty,
          reason: '${spec.typeId} 的密文键 ${spec.secretFieldKeys} 超出清点清单'
              '（新密文键要先定性再进加密范围）',
        );
      }
    });
  });
}
