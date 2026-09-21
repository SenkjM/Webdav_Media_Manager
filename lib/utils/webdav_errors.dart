/// Detect permission / auth failures from WebDAV / Dio errors.
bool isWebDavPermissionError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('401') || s.contains('403')) return true;
  if (s.contains('unauthorized') || s.contains('forbidden')) return true;
  if (s.contains('permission denied') || s.contains('insufficient')) {
    return true;
  }
  if (s.contains('access denied') || s.contains('not allowed')) return true;
  return false;
}

String webDavErrorMessage(Object error) {
  if (isWebDavPermissionError(error)) {
    return '权限不足或未授权（401/403）';
  }
  return error.toString();
}
