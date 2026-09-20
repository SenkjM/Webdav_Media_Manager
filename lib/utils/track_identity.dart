/// Unique binding between a network disk account and a remote path.
/// Never rely on filename alone across accounts.
String trackIdentityKey(String accountId, String remotePath) {
  return '$accountId\u0000$remotePath';
}

/// Stable cache / cover file stem derived from identity key.
String identityHashStem(String accountId, String remotePath) {
  return trackIdentityKey(accountId, remotePath).hashCode.toRadixString(16);
}
