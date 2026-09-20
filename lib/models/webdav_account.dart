/// A configured WebDAV server (credentials stored separately in secure storage).
class WebDavAccount {
  const WebDavAccount({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
  });

  final String id;
  final String name;
  final String url;
  final String username;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
      };

  factory WebDavAccount.fromMap(Map<String, dynamic> map) => WebDavAccount(
        id: map['id'] as String,
        name: map['name'] as String,
        url: map['url'] as String,
        username: map['username'] as String? ?? '',
      );

  WebDavAccount copyWith({
    String? name,
    String? url,
    String? username,
  }) {
    return WebDavAccount(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
    );
  }
}
