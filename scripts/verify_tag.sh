#!/usr/bin/env bash
# 硬指标复核：归档完整性 + 解压结果与 zip 条目数对账。
#
# 用法:
#   bash scripts/verify_tag.sh <TAG> [归档根]
#
# 判据（唯一实现，四个调用方共用：人工复核 / run.sh / archive_one.sh / 事后审计）:
#   A. zip 与 tar.gz 在**临时目录副本**上分别通过 `unzip -tq` 与 `tar -tzf`；
#   B. 解压目录内 `find -type f` + `find -type l` == zip 非目录条目数；
#   C. 解压目录内失效符号链接数 == 0。
#
# 为什么必须在副本上校验：在本机目标盘（D:/G:）直接跑 tar/unzip 会不可靠地报假失败，
# 见 docs/LESSONS.md 第 1 条。
#
# 解压侧约定（v1.2.0 起）：解压统一由 archive_one.sh 用 **tar.gz** 完成 —— zip 里的
# 符号链接条目，Info-ZIP unzip 在 Windows 上无法物化（静默缺条目 ⇒ B 必然 FAIL），
# tar 则能确定性物化（真链或内容拷贝），见 docs/LESSONS.md 第 12 条。
# zip 在此仍承担两个角色：A 的完整性校验对象 + B 的条目数基准清单。
#
# 历史现象（v1.1.x，仅 zip 解压路径）：Git Bash 的 unzip 建符号链接时打印
# `symlink error: File exists`，该行不参与判定 —— 只看 A/B/C 三条。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
load_env "$HERE"

TAG="${1:-}"
ROOT="${2:-${DSH_ARCHIVE_ROOT:-}}"

if [ -z "$TAG" ]; then
  echo "用法: bash scripts/verify_tag.sh <TAG> [归档根]" >&2
  exit 2
fi
if [ -z "$ROOT" ]; then
  echo "ERROR: 未给出归档根。用第二个参数或环境变量 DSH_ARCHIVE_ROOT 指定。" >&2
  exit 2
fi

PROJ="${REPO##*/}"
ZIP="$ROOT/${TAG}-source.zip"
TGZ="$ROOT/${TAG}-source.tar.gz"
DIR="$ROOT/extracted/${PROJ}-${TAG}"

status=PASS
fail() { status=FAIL; echo "FAIL: $*" >&2; }

# --- A. 归档完整性（临时目录副本） -----------------------------------------
TMP="$(tmp_root)/_dshv.$$"
mkdir -p "$TMP"

for pair in "zip:$ZIP" "tar.gz:$TGZ"; do
  ext="${pair%%:*}"; src="${pair#*:}"
  if [ ! -s "$src" ]; then
    fail "缺少归档或为空: $src"
    continue
  fi
  cp "$src" "$TMP/v.$ext" || { fail "复制到临时目录失败: $src"; continue; }
  if [ "$ext" = "zip" ]; then
    unzip -tq "$TMP/v.zip" >/dev/null 2>&1 || fail "zip 完整性校验不通过: $src"
  else
    tar -tzf "$TMP/v.tar.gz" >/dev/null 2>&1 || fail "tar.gz 完整性校验不通过: $src"
  fi
done

# --- B/C. 解压结果对账 ------------------------------------------------------
if [ ! -d "$DIR" ]; then
  fail "解压目录不存在: $DIR"
  echo "RESULT tag=${TAG} status=FAIL reason=no-extracted-dir"
  exit 1
fi

ENTRIES=$(unzip -Z1 "$ZIP" 2>/dev/null | grep -v '/$' | wc -l | tr -d ' ')
FILES=$(find "$DIR" -type f | wc -l | tr -d ' ')
LINKS=$(find "$DIR" -type l | wc -l | tr -d ' ')
BROKEN=$(find "$DIR" -type l ! -exec test -e {} \; 2>/dev/null | wc -l | tr -d ' ')
SUM=$((FILES + LINKS))

[ "$SUM" = "$ENTRIES" ] || fail "条目数不符: 文件 ${FILES} + 链接 ${LINKS} = ${SUM} ≠ zip 非目录条目 ${ENTRIES}"
[ "$BROKEN" = "0" ] || fail "存在失效符号链接 ${BROKEN} 条"

echo "RESULT tag=${TAG} files=${FILES} symlinks=${LINKS} entries=${ENTRIES} broken=${BROKEN} status=${status}"
[ "$status" = "PASS" ] || exit 1
exit 0
