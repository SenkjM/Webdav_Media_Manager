#!/usr/bin/env bash
# 版本标签门禁。release / prerelease 共用同一套合法与递增规则。
# 合法：vX.Y.Z，每段 0–99，不要前导零。只能严格大于已有最高合法标签。
set -euo pipefail

: "${GATE_MODE:?}"
: "${EVENT_NAME:?}"
: "${REPO:?}"
: "${OWNER:?}"
: "${RUN_URL:?}"
: "${GITHUB_OUTPUT:?}"

is_legal() {
  printf '%s' "$1" | grep -Eq '^v(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)\.(0|[1-9][0-9]?)$'
}

split_ver() {
  local t="${1#v}"
  SPLIT_MAJOR="${t%%.*}"
  local rest="${t#*.}"
  SPLIT_MINOR="${rest%%.*}"
  SPLIT_PATCH="${rest#*.}"
}

version_code() {
  echo $(( $1 * 100000000 + $2 * 1000000 + $3 * 10000 + $4 ))
}

cmp_ver() {
  split_ver "$1"
  local a1=$SPLIT_MAJOR a2=$SPLIT_MINOR a3=$SPLIT_PATCH
  split_ver "$2"
  local b1=$SPLIT_MAJOR b2=$SPLIT_MINOR b3=$SPLIT_PATCH
  if [ "$a1" -gt "$b1" ]; then echo gt; return; fi
  if [ "$a1" -lt "$b1" ]; then echo lt; return; fi
  if [ "$a2" -gt "$b2" ]; then echo gt; return; fi
  if [ "$a2" -lt "$b2" ]; then echo lt; return; fi
  if [ "$a3" -gt "$b3" ]; then echo gt; return; fi
  if [ "$a3" -lt "$b3" ]; then echo lt; return; fi
  echo eq
}

collect_logins() {
  LOGINS=""
  local owner_type login
  owner_type="$(gh api "users/${OWNER}" --jq .type 2>/dev/null || true)"
  if [ "$owner_type" = "User" ]; then
    LOGINS="$OWNER"
  fi
  while IFS= read -r login; do
    [ -z "$login" ] && continue
    case " ${LOGINS} " in
      *" ${login} "*) ;;
      *) LOGINS="${LOGINS} ${login}" ;;
    esac
  done < <(gh api --paginate "repos/${REPO}/collaborators" --jq '.[] | select((.permissions.admin == true) or (.permissions.push == true) or (.permissions.maintain == true) or (.role_name == "admin") or (.role_name == "write") or (.role_name == "maintain")) | .login' 2>/dev/null || true)
  LOGINS="$(printf '%s' "$LOGINS" | xargs || true)"
}

notify() {
  local title="$1"
  local detail="$2"
  local existing
  existing="$(gh issue list --repo "$REPO" --state open --limit 100 --json title,number | jq -r --arg t "$title" '.[] | select(.title == $t) | .number' | head -n 1 || true)"
  if [ -n "${existing}" ]; then
    echo "Issue already open: #${existing}"
    return 0
  fi
  collect_logins
  if [ -z "${LOGINS}" ]; then
    echo "No owner or collaborators to notify; skipping."
    return 0
  fi
  local mentions="" login body url
  for login in ${LOGINS}; do
    mentions="${mentions} @${login}"
  done
  body="$(printf '%s\n\n%s\n' "${mentions# }" "$detail")"
  url="$(gh issue create --repo "$REPO" --title "$title" --body "$body")"
  for login in ${LOGINS}; do
    gh issue edit --repo "$REPO" "$url" --add-assignee "$login" || echo "Skip assignee ${login}"
  done
}

set_out() {
  printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

fail_illegal() {
  local tag="$1"
  local reason="$2"
  local detail
  detail="$(printf '标签 `%s` 未通过发版检查，已保留，未构建。\n\n- 原因：%s\n- 推送者：%s\n- 运行：%s\n\n请自行删除或更正该标签。Action 不会删除它。\n' "$tag" "$reason" "${ACTOR:-unknown}" "$RUN_URL")"
  notify "非法 tag：${tag}" "$detail" || echo "::warning::通知失败，标签已保留。"
  set_out proceed false
  exit 1
}

remind_missing() {
  local detail
  detail="$(printf '没有合法的 vX.Y.Z 标签，自动构建已停止，未打标签，未编译。\n\n请到 Actions 手动触发正式版，填写版本号。流程会先给当前 main 打上该标签，再做合法性与递增检查。\n\n- 运行：%s\n' "$RUN_URL")"
  notify "缺少合法版本标签" "$detail" || echo "::warning::提醒失败。"
  set_out proceed false
}

highest_other() {
  local self="$1"
  local best="" t rel
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    [ "$t" = "$self" ] && continue
    is_legal "$t" || continue
    if [ -z "$best" ]; then
      best="$t"
      continue
    fi
    rel="$(cmp_ver "$t" "$best")"
    if [ "$rel" = "gt" ]; then
      best="$t"
    fi
  done < <(git tag -l 'v*')
  printf '%s' "$best"
}

ensure_release_tag() {
  if [ "${REF_NAME}" != "main" ]; then
    echo "::error::手动发版只允许从 main 触发（当前引用：${REF_NAME}）。"
    exit 1
  fi
  local raw="${INPUT_VERSION:-}"
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  if [ -z "$raw" ]; then
    remind_missing
    exit 1
  fi
  case "$raw" in
    v*) TAG="$raw" ;;
    *) TAG="v${raw}" ;;
  esac
  if ! printf '%s' "$TAG" | grep -Eq '^v[0-9A-Za-z._+-]+$'; then
    local detail
    detail="$(printf '版本号无法形成 git 标签：`%s`。未打标签，未构建。\n\n- 运行：%s\n' "${INPUT_VERSION:-}" "$RUN_URL")"
    notify "版本号无法形成标签" "$detail" || echo "::warning::提醒失败。"
    set_out proceed false
    exit 1
  fi
  git fetch origin main --tags --force
  local main_sha old
  main_sha="$(git rev-parse origin/main)"
  if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    old="$(git rev-parse "refs/tags/${TAG}^{}")"
    if [ "$old" != "$main_sha" ]; then
      fail_illegal "$TAG" "标签已存在且不指向当前 main（${main_sha}），拒绝移动。"
    fi
    echo "Tag ${TAG} already points at current main."
  else
    git tag "$TAG" "$main_sha"
    git push origin "refs/tags/${TAG}:refs/tags/${TAG}"
    echo "Created ${TAG} on ${main_sha}"
  fi
  SHA="$main_sha"
}

check_release_tag() {
  if ! is_legal "$TAG"; then
    fail_illegal "$TAG" "不符合 vX.Y.Z。每一段必须是 0–99 的数字，且不能有前导零。"
  fi
  split_ver "$TAG"
  local release_code pre_max best rel short compare
  release_code="$(version_code "$SPLIT_MAJOR" "$SPLIT_MINOR" "$SPLIT_PATCH" 0)"
  pre_max="$(version_code "$SPLIT_MAJOR" "$SPLIT_MINOR" "$SPLIT_PATCH" 999)"
  if [ "$release_code" -lt 1 ] || [ "$pre_max" -gt 2100000000 ]; then
    fail_illegal "$TAG" "versionCode 放不进 1..2100000000（正式版 ${release_code}，预发布上限 ${pre_max}）。主版本实际只能到 20。"
  fi
  git fetch origin main --tags --force
  if ! git merge-base --is-ancestor "$SHA" origin/main; then
    fail_illegal "$TAG" "标签指向的提交不在 main 历史上。"
  fi
  best="$(highest_other "$TAG")"
  if [ -n "$best" ]; then
    rel="$(cmp_ver "$TAG" "$best")"
    if [ "$rel" != "gt" ]; then
      fail_illegal "$TAG" "版本没有严格大于当前最高合法标签 ${best}。"
    fi
  fi
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release ${TAG} already exists; skip build."
    set_out proceed false
    exit 0
  fi
  short="$(git rev-parse --short=7 "$SHA" | cut -c1-7)"
  if [ -n "$best" ]; then
    compare="变更对比：https://github.com/${REPO}/compare/${best}...${TAG}"
  else
    compare="（首个正式版，无对比基准）"
  fi
  set_out proceed true
  set_out tag "$TAG"
  set_out version_name "$TAG"
  set_out version_code "$release_code"
  set_out short_sha "$short"
  set_out prev_tag "$best"
  set_out compare "$compare"
  set_out sha "$SHA"
}

mode_release() {
  git fetch origin main --tags --force
  if [ "$EVENT_NAME" = "workflow_dispatch" ]; then
    ensure_release_tag
  else
    TAG="${REF_NAME}"
    SHA="$(git rev-parse "refs/tags/${TAG}^{}")"
  fi
  check_release_tag
}

mode_prerelease() {
  if [ "$EVENT_NAME" != "schedule" ] && [ "${REF_NAME}" != "main" ]; then
    echo "::warning::预发布只从 main 发布（当前 ${REF_NAME}）。本次不构建。"
    set_out proceed false
    exit 0
  fi
  git fetch origin main --tags --force
  git checkout --detach origin/main
  local base head release_sha last="" seq=1
  base="$(highest_other "")"
  if [ -z "$base" ]; then
    remind_missing
    exit 0
  fi
  head="$(git rev-parse HEAD)"
  release_sha="$(git rev-parse "${base}^{}")"
  if git rev-parse -q --verify refs/tags/prerelease >/dev/null; then
    last="$(git rev-parse "refs/tags/prerelease^{}")"
  fi
  local old_base="" old_seq="" old_sha="" msg body published_sha=""
  body="$(gh release view prerelease --repo "$REPO" --json body --jq .body 2>/dev/null || true)"
  published_sha="$(printf '%s\n' "$body" | sed -n 's/^sha=//p' | head -n 1 || true)"
  if [ -n "$last" ]; then
    msg="$(git tag -l --format='%(contents)' prerelease || true)"
    old_base="$(printf '%s\n' "$msg" | sed -n 's/^base_tag=//p' | head -n 1 || true)"
    old_seq="$(printf '%s\n' "$msg" | sed -n 's/^seq=//p' | head -n 1 || true)"
    old_sha="$(printf '%s\n' "$msg" | sed -n 's/^sha=//p' | head -n 1 || true)"
  fi
  if [ -z "$old_seq" ]; then
    old_base="$(printf '%s\n' "$body" | sed -n 's/^base_tag=//p' | head -n 1 || true)"
    old_seq="$(printf '%s\n' "$body" | sed -n 's/^seq=//p' | head -n 1 || true)"
    old_sha="$(printf '%s\n' "$body" | sed -n 's/^sha=//p' | head -n 1 || true)"
  fi
  if [ "$EVENT_NAME" != "workflow_dispatch" ]; then
    if [ -n "$published_sha" ] && [ "$published_sha" = "$head" ]; then
      echo "main 的该提交已经发过 Pre-release。"
      set_out proceed false
      exit 0
    fi
    if [ -n "$old_sha" ] && [ "$old_sha" = "$head" ]; then
      echo "main 的该提交已经记入 prerelease 标签。"
      set_out proceed false
      exit 0
    fi
    if [ "$head" = "$release_sha" ]; then
      echo "main 与正式标签指向同一提交，跳过预发布。"
      set_out proceed false
      exit 0
    fi
  fi
  if ! printf '%s' "$old_seq" | grep -Eq '^[0-9]+$'; then
    old_seq=""
  fi
  if [ -n "$old_sha" ] && [ "$old_sha" = "$head" ] && [ -n "$old_seq" ]; then
    seq="$old_seq"
  elif [ -n "$old_base" ] && [ "$old_base" = "$base" ] && [ -n "$old_seq" ]; then
    seq=$((old_seq + 1))
  fi
  if [ "$seq" -gt 999 ]; then
    notify "预发布序号已用尽：${base}" "$(printf '基准标签 %s 的后三位已到 999，未构建。\n\n- 运行：%s\n' "$base" "$RUN_URL")" || true
    set_out proceed false
    exit 1
  fi
  split_ver "$base"
  local code short name
  code="$(version_code "$SPLIT_MAJOR" "$SPLIT_MINOR" "$SPLIT_PATCH" "$seq")"
  if [ "$code" -gt 2100000000 ]; then
    notify "预发布 versionCode 超限：${base}" "$(printf '计算出的 versionCode %s 超过 2100000000，未构建。\n\n- 运行：%s\n' "$code" "$RUN_URL")" || true
    set_out proceed false
    exit 1
  fi
  short="$(git rev-parse --short=7 HEAD | cut -c1-7)"
  name="${base}-${short}"
  set_out proceed true
  set_out version_name "$name"
  set_out version_code "$code"
  set_out short_sha "$short"
  set_out base_tag "$base"
  set_out sha "$head"
  set_out seq "$seq"
  set_out tag "$base"
}

case "$GATE_MODE" in
  release) mode_release ;;
  prerelease) mode_prerelease ;;
  *) echo "::error::unknown GATE_MODE=$GATE_MODE"; exit 1 ;;
esac
