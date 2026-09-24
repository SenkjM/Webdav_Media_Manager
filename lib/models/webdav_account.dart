import 'account_capabilities.dart';

/// A configured remote account (credentials stored separately in secure storage).
///
/// [providerType] 决定账号走哪条实现：`'webdav'` 走 WebDAV 客户端，其余值对应
/// 云盘驱动（99 §7）。[remotePath] 限定浏览根（默认 `/`，空置视为 `/`）。
/// [capabilities] 仅对 WebDAV 账号生效（用户可配，默认全量）；云盘类型由
/// [AccountCaps] 的静态表给定，行里的值被忽略。
class WebDavAccount {
  const WebDavAccount({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    this.providerType = 'webdav',
    this.remotePath = '/',
    this.capabilities = AccountCaps.all,
  });

  final String id;
  final String name;
  final String url;
  final String username;
  final String providerType;
  final String remotePath;
  final int capabilities;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'provider_type': providerType,
        'remote_path': remotePath,
        'capabilities': capabilities,
      };

  factory WebDavAccount.fromMap(Map<String, dynamic> map) => WebDavAccount(
        id: map['id'] as String,
        name: map['name'] as String,
        url: map['url'] as String,
        username: map['username'] as String? ?? '',
        providerType: map['provider_type'] as String? ?? 'webdav',
        remotePath:
            WebDavAccount.normalizeRemotePath(map['remote_path'] as String? ?? '/'),
        capabilities:
            AccountCaps.normalizeStored((map['capabilities'] as int?) ?? AccountCaps.all),
      );

  WebDavAccount copyWith({
    String? name,
    String? url,
    String? username,
    String? providerType,
    String? remotePath,
    int? capabilities,
  }) {
    return WebDavAccount(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      providerType: providerType ?? this.providerType,
      remotePath: remotePath ?? this.remotePath,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  /// 远程路径归一：空 → `/`；缺前导 `/` 补上；结尾 `/` 只保留根那一个。
  static String normalizeRemotePath(String value) {
    var p = value.trim();
    if (p.isEmpty) return '/';
    if (!p.startsWith('/')) p = '/$p';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}
