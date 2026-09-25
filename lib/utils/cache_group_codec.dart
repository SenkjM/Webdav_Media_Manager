import 'dart:convert';

/// Codec for the runtime「CUE 整专辑一组」membership, plus the parser for the
/// legacy prefs layout (99 §6.2 T1).
///
/// Membership lives in `music_library.db` table `cache_groups`
/// (`group_id` PK + JSON `members`). It used to live in SharedPreferences
/// under two `String.hashCode`-suffixed keys, which can collide and cross
/// groups. [parseLegacyCacheGroups] reads that old layout once so the values
/// can be written into the new table before the keys are dropped.

/// Encode the member identity list persisted in `cache_groups.members`.
///
/// Identities are `sourceName\u0000remotePath` ([trackIdentityKey]).
String encodeCacheGroupMembers(Iterable<String> members) =>
    jsonEncode(members.where((m) => m.isNotEmpty).toList());

/// Decode `cache_groups.members`; tolerant of null / corrupt values.
List<String> decodeCacheGroupMembers(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return (jsonDecode(raw) as List)
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Split a `sourceName\u0000remotePath` identity back into its parts.
///
/// The remote path may itself contain `\u0000` in legacy data, so only the
/// first separator splits (matching the old inline parsing).
({String sourceName, String remotePath})? splitCacheIdentity(String identity) {
  final parts = identity.split('\u0000');
  if (parts.isEmpty) return null;
  final sourceName = parts.first;
  final remotePath =
      parts.length > 1 ? parts.sublist(1).join('\u0000') : identity;
  return (sourceName: sourceName, remotePath: remotePath);
}

// --- Legacy SharedPreferences layout ---

/// `cache_group_<identity.hashCode>` → group id.
const String legacyCacheGroupKeyPrefix = 'cache_group_';

/// `cache_group_members_<groupId.hashCode>` → JSON identity list. Note this
/// shares [legacyCacheGroupKeyPrefix] as a prefix; checks must test the longer
/// one first or the group-id branch will swallow it.
const String legacyCacheGroupMembersKeyPrefix = 'cache_group_members_';

/// `cache_access_<identity.hashCode>` → ISO-8601 last-access timestamp.
const String legacyCacheAccessKeyPrefix = 'cache_access_';

/// One group recovered from the legacy prefs layout.
class LegacyCacheGroup {
  const LegacyCacheGroup({required this.groupId, required this.members});

  final String groupId;
  final List<String> members;
}

/// Recover `(groupId, members)` pairs from the legacy prefs key/value dump.
///
/// Both legacy keys are suffixed with `String.hashCode` and are therefore
/// **not reversible**: the member list is in the value (usable), while the
/// per-path group id only exists in the `cache_group_<identity.hashCode>`
/// values. The group id is resolved two ways and anything unresolvable is
/// skipped (the files themselves are untouched; only the group view degrades).
List<LegacyCacheGroup> parseLegacyCacheGroups(Map<String, String> entries) {
  final memberKeys = <String, String>{};
  final candidateIds = <String>{};
  entries.forEach((key, value) {
    if (key.startsWith(legacyCacheGroupMembersKeyPrefix)) {
      memberKeys[key] = value;
    } else if (key.startsWith(legacyCacheGroupKeyPrefix) &&
        value.isNotEmpty) {
      candidateIds.add(value);
    }
  });
  if (memberKeys.isEmpty) return const [];

  // The old code stored the group id under its own String.hashCode, so a
  // candidate id whose hashCode matches the members-key suffix is the owner.
  final byHash = <String, String>{};
  for (final id in candidateIds) {
    byHash['${id.hashCode}'] = id;
  }

  final out = <LegacyCacheGroup>[];
  final seen = <String>{};
  for (final entry in memberKeys.entries) {
    final members = decodeLegacyMemberList(entry.value);
    if (members.isEmpty) continue;
    final suffix =
        entry.key.substring(legacyCacheGroupMembersKeyPrefix.length);
    final groupId =
        byHash[suffix] ?? _resolveGroupIdFromMembers(members, entries);
    if (groupId == null || groupId.isEmpty) continue;
    if (!seen.add(groupId)) continue;
    out.add(LegacyCacheGroup(groupId: groupId, members: members));
  }
  return out;
}

/// Parse one legacy `cache_group_members_*` value.
List<String> decodeLegacyMemberList(String raw) {
  if (raw.isEmpty) return const [];
  try {
    return (jsonDecode(raw) as List)
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

String? _resolveGroupIdFromMembers(
  List<String> members,
  Map<String, String> entries,
) {
  for (final identity in members) {
    final value = entries['$legacyCacheGroupKeyPrefix${identity.hashCode}'];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
