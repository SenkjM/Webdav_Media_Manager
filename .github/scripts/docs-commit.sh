#!/usr/bin/env bash
# 识别文档 / CI 专用提交的共享辅助函数。
# 由 commit-list.sh 与 version-gate.sh 共同 source；本身不含任何可运行主体。
#
# 识别规则（与 docs/00-INDEX.md §3.7 的命名规范一致）：
#   1. 主题以 docs: / docs(scope): 或 ci: / ci(scope): 开头（大小写不敏感）；
#   2. 或该提交只改动了文档路径（docs/、*.md、*.txt 等），且不含代码文件。

# is_docs_commit subject full_sha
# 返回 0 = 文档 / CI 专用提交；返回 1 = 含代码改动。
is_docs_commit() {
  local subject="$1" full="$2"
  # 规则 1：约定前缀。
  if printf '%s' "$subject" | grep -qiE '^(docs|ci)(\([^)]*\))?!?:'; then
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
