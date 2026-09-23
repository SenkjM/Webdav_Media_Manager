/// 远端路径的层级工具。只做字符串处理，不碰网络。
///
/// 目录选择器要用它把「当前目录」展开成可逐级返回的栈——只把整条路径当
/// 一层的话，「上一级」会一步跳回根目录。
library;

/// 把 `/a/b/c` 展开成 `['/a', '/a/b', '/a/b/c']`（不含根）。
///
/// 多余的分隔符与结尾斜杠会被忽略：`/a//b/` 与 `/a/b` 结果相同。
List<String> remoteAncestors(String path) {
  final out = <String>[];
  var current = '';
  for (final segment in path.split('/')) {
    if (segment.isEmpty) continue;
    current = '$current/$segment';
    out.add(current);
  }
  return out;
}

/// 上一级目录；已经是根目录时返回 null。
String? remoteParent(String path) {
  final stack = remoteAncestors(path);
  if (stack.isEmpty) return null;
  if (stack.length == 1) return '/';
  return stack[stack.length - 2];
}
