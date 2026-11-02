#!/usr/bin/env bash
# 只读检测：本地归档缺哪些远端 release tag。
#
# 用法:
#   bash scripts/weekly_check.sh
#
# 输出（可直接粘进汇报）:
#   REPO=<owner>/<repo>
#   LOCAL_TAGS=<n>
#   REMOTE_TAGS=<n>
#   NEW_TAGS=<tag1 tag2 ...>        # 空则表示无新增
#
# 退出码: 0 正常（无论有无新增）/ 2 用法或环境问题 / 3 网络或 API 失败
# 纪律：本脚本**只读**，不下载、不删除、不改归档根任何内容。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
# shellcheck source=../config/target.env
. "$HERE/../config/target.env"

ROOT="${DSH_ARCHIVE_ROOT:-}"
if [ -z "$ROOT" ]; then
  echo "ERROR: 未设置 DSH_ARCHIVE_ROOT（归档根）。" >&2
  exit 2
fi
if [ ! -d "$ROOT" ]; then
  echo "ERROR: 归档根不存在: $ROOT" >&2
  exit 2
fi

TMP="$(tmp_root)/_dshw.$$"
mkdir -p "$TMP"

# --- 本地已有 tag：文件名形如 <TAG>-source.zip ------------------------------
for f in "$ROOT"/*-source.zip; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  printf '%s\n' "${b%-source.zip}"
done | sort -u > "$TMP/local.txt"

# --- 远端 release tag ------------------------------------------------------
api="https://api.github.com/repos/${REPO}/releases?per_page=${PER_PAGE}"
if ! curl -fsSL --connect-timeout 20 --max-time 60 -o "$TMP/rel.json" "$api"; then
  echo "ERROR: 拉取 release 列表失败: $api" >&2
  exit 3
fi
grep -E '"tag_name"' "$TMP/rel.json" \
  | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
  | sort -u > "$TMP/remote.txt"

REMOTE_N=$(wc -l < "$TMP/remote.txt" | tr -d ' ')
if [ "$REMOTE_N" = "0" ]; then
  echo "ERROR: 未解析到任何 tag（可能是 API 限流或字段变更）: $api" >&2
  head -3 "$TMP/rel.json" >&2
  exit 3
fi

# --- 差集：远端有、本地无 ---------------------------------------------------
comm -13 "$TMP/local.txt" "$TMP/remote.txt" > "$TMP/new.txt"

LOCAL_N=$(wc -l < "$TMP/local.txt" | tr -d ' ')
NEW_TAGS=$(tr '\n' ' ' < "$TMP/new.txt" | sed -E 's/[[:space:]]+$//')

echo "REPO=${REPO}"
echo "LOCAL_TAGS=${LOCAL_N}"
echo "REMOTE_TAGS=${REMOTE_N}"
echo "NEW_TAGS=${NEW_TAGS}"
if [ -z "$NEW_TAGS" ]; then
  echo "NO_NEW_RELEASES"
fi
exit 0
