// 登记指纹：CloudDriveService.registerAccounts「配置没变就不重建驱动」的判据。
//
// 背景：启动、每次进出账号页 / 网络库 / 同步页都会调 registerAccounts，而重建
// 驱动会丢掉驱动内部的 path→id 缓存、直链解析缓存与连接池（真机表现为浏览深层
// 目录重复解析、播放中途重新解析直链）。判据必须**不放过任何真实的配置变更**，
// 否则驱动会继续用旧配置；也不能把「驱动自己写回的令牌」当成用户改配置，否则
// 一次令牌轮换就白重建一遍。

import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_media_manager/models/webdav_account.dart';
import 'package:webdav_media_manager/services/cloud_drive_service.dart';

WebDavAccount account({
  String id = 'a1',
  String name = '我的盘',
  String providerType = 'baidu_netdisk',
  String remotePath = '/',
}) =>
    WebDavAccount(
      id: id,
      name: name,
      url: '',
      username: '',
      providerType: providerType,
      remotePath: remotePath,
    );

void main() {
  group('cloudAccountSignature', () {
    test('同一账号 + 同一配置 → 指纹相同', () {
      final cfg = <String, dynamic>{'refresh_token': 't', 'local_refresh': true};
      expect(
        cloudAccountSignature(account(), cfg),
        cloudAccountSignature(account(), {...cfg}),
      );
    });

    test('配置键的写入顺序不影响指纹', () {
      expect(
        cloudAccountSignature(account(), {'a': 1, 'b': 'x', 'c': false}),
        cloudAccountSignature(account(), {'c': false, 'b': 'x', 'a': 1}),
      );
    });

    test('任何一个配置值变化都换指纹（不能漏字段）', () {
      final base = <String, dynamic>{'refresh_token': 't', 'source_dir': '/'};
      final sig = cloudAccountSignature(account(), base);
      expect(cloudAccountSignature(account(), {...base, 'source_dir': '/sub'}),
          isNot(sig));
      expect(cloudAccountSignature(account(), {...base, 'new_key': 'v'}),
          isNot(sig));
      expect(cloudAccountSignature(account(), {'refresh_token': 't'}), isNot(sig),
          reason: '少一个键也算变（例如被外部写坏了配置）');
    });

    test('账号侧字段变化换指纹：名字 / 类型 / 浏览根', () {
      final cfg = <String, dynamic>{'k': 'v'};
      final sig = cloudAccountSignature(account(), cfg);
      expect(cloudAccountSignature(account(name: '改了名'), cfg), isNot(sig));
      expect(cloudAccountSignature(account(providerType: 'crypt'), cfg),
          isNot(sig));
      expect(cloudAccountSignature(account(remotePath: '/sub'), cfg), isNot(sig));
    });

    test('配置缺失（null）与空配置同形', () {
      expect(cloudAccountSignature(account(), null),
          cloudAccountSignature(account(), const <String, dynamic>{}));
    });
  });

  group('cloudRegistrationSignature', () {
    test('账号遍历顺序不影响整批指纹', () {
      final a = cloudAccountSignature(account(id: 'a1'), {'k': '1'});
      final b = cloudAccountSignature(account(id: 'a2'), {'k': '2'});
      expect(cloudRegistrationSignature({'a1': a, 'a2': b}),
          cloudRegistrationSignature({'a2': b, 'a1': a}));
    });

    test('新增 / 删除账号换整批指纹（删除的驱动会被回收）', () {
      final a = cloudAccountSignature(account(id: 'a1'), {'k': '1'});
      final b = cloudAccountSignature(account(id: 'a2'), {'k': '2'});
      final one = cloudRegistrationSignature({'a1': a});
      expect(cloudRegistrationSignature({'a1': a, 'a2': b}), isNot(one));
      expect(cloudRegistrationSignature({'a2': b}), isNot(one));
    });

    test('令牌轮换（驱动写回配置）后整批指纹与「重新读一遍存储」一致', () {
      // _persistTokens 的语义：就地更新该账号的指纹后重算整批指纹，
      // 结果必须等于「下次 registerAccounts 从存储里读到的配置」算出来的值。
      final cfg = <String, dynamic>{'refresh_token': 'old'};
      final before = {
        'a1': cloudAccountSignature(account(id: 'a1'), cfg),
        'a2': cloudAccountSignature(account(id: 'a2'), {'k': '2'}),
      };
      final rotated = <String, dynamic>{...cfg, 'refresh_token': 'new'};
      final after = {
        'a1': cloudAccountSignature(account(id: 'a1'), rotated),
        'a2': before['a2']!,
      };
      expect(cloudRegistrationSignature(after),
          isNot(cloudRegistrationSignature(before)),
          reason: '指纹本身会变——正因为如此才要在写回时同步整批指纹');
      final reread = {
        'a1': cloudAccountSignature(account(id: 'a1'), rotated),
        'a2': cloudAccountSignature(account(id: 'a2'), {'k': '2'}),
      };
      expect(cloudRegistrationSignature(after),
          cloudRegistrationSignature(reread),
          reason: '同步后的整批指纹 == 下次登记重算出来的整批指纹（否则会白重建）');
    });
  });
}
