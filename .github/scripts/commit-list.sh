#!/usr/bin/env bash
# 打印 from..to 的提交列表。每行：短哈希链接 + 标题。
# from 为空表示没有上一正式版。
set -euo pipefail

from="${1:-}"
to="${2:?}"
: "${REPO:?}"
server="${GITHUB_SERVER_URL:-https://github.com}"

if [ -z "$from" ]; then
  printf '%s\n' "无上一正式版。"
  exit 0
fi

git fetch origin --tags --force >/dev/null
if ! git rev-parse -q --verify "${from}^{commit}" >/dev/null; then
  printf '找不到基准 %s。\n' "$from"
  exit 0
fi
if ! git rev-parse -q --verify "${to}^{commit}" >/dev/null; then
  printf '找不到目标提交 %s。\n' "$to"
  exit 0
fi

count="$(git rev-list --count "${from}..${to}")"
if [ "$count" = "0" ]; then
  printf '%s\n' "没有新提交。"
  exit 0
fi

git log --reverse --format='%H%x09%s' "${from}..${to}" | while IFS=$'\t' read -r full subject; do
  short="${full:0:7}"
  printf -- '- [`%s`](%s/%s/commit/%s) %s\n' "$short" "$server" "$REPO" "$full" "$subject"
done
