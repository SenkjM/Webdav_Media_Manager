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

# 过滤纯文档提交：release notes 面向使用者，只列功能/修复相关的改动。
# 识别规则（与 docs/00-INDEX.md §3.7 的命名规范一致）：
#   1. 主题以 docs: 或 docs(scope): 开头（大小写不敏感）；
#   2. 或该提交只改动了文档路径（docs/ 、*.md、99 文档等），且不含代码文件。
is_docs_commit() {
  local subject="$1" full="$2"
  # 规则 1：约定前缀。
  if printf '%s' "$subject" | grep -qiE '^docs(\([^)]*\))?!?:'; then
    return 0
  fi
  # 规则 2：提交里的改动全是文档（没有非文档文件）。
  local files
  files="$(git show --pretty=format: --name-only "$full" | sed '/^$/d')"
  [ -n "$files" ] || return 1
  local f
  while IFS= read -r f; do
    case "$f" in
      *.md|docs/*|*.txt|.github/*.md|LICENSE*|README*) ;;
      *) return 1 ;;
    esac
  done <<< "$files"
  return 0
}

shown=0
while IFS=$'\t' read -r full subject; do
  if is_docs_commit "$subject" "$full"; then
    continue
  fi
  short="${full:0:7}"
  printf -- '- [`%s`](%s/%s/commit/%s) %s\n' "$short" "$server" "$REPO" "$full" "$subject"
  shown=$((shown + 1))
done < <(git log --reverse --format='%H%x09%s' "${from}..${to}")

if [ "$shown" = "0" ]; then
  printf '%s\n' "（本次只有文档改动。）"
fi
