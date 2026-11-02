#!/usr/bin/env bash
# 单个 tag 的全流程：下载两份归档 → 校验 → 解压 → 硬指标复核。
#
# 用法:
#   bash scripts/archive_one.sh <TAG> [归档根]
#
# 设计要点:
#   - **串行**：zip 下完再下 tar.gz，绝不并行（并行会 fork 失败，见 docs/LESSONS.md 第 2 条）；
#   - **幂等**：已存在且通过校验的归档会被 dl_one.sh 跳过；已解压的目录不重复解压；
#   - **判据单一**：判定一律委托 verify_tag.sh，本脚本不另写一套阈值。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
load_env "$HERE"

TAG="${1:-}"
ROOT="${2:-${DSH_ARCHIVE_ROOT:-}}"

if [ -z "$TAG" ]; then
  echo "用法: bash scripts/archive_one.sh <TAG> [归档根]" >&2
  exit 2
fi
if [ -z "$ROOT" ]; then
  echo "ERROR: 未给出归档根。用第二个参数或环境变量 DSH_ARCHIVE_ROOT 指定。" >&2
  exit 2
fi
mkdir -p "$ROOT" || exit 2

PROJ="${REPO##*/}"
DIR="$ROOT/extracted/${PROJ}-${TAG}"

echo "== [1/4] 下载 zip =="
bash "$HERE/dl_one.sh" "$REPO" "$TAG" "$ROOT" zip || { echo "RESULT tag=${TAG} status=FAIL stage=download-zip"; exit 1; }

echo "== [2/4] 下载 tar.gz =="
bash "$HERE/dl_one.sh" "$REPO" "$TAG" "$ROOT" tar.gz || { echo "RESULT tag=${TAG} status=FAIL stage=download-targz"; exit 1; }

echo "== [3/4] 解压 =="
if [ -d "$DIR" ]; then
  echo "SKIP 已解压: $DIR"
else
  ERRF="$(tmp_root)/_dshu.$$.err"
  ( cd "$ROOT" && unzip -q "${TAG}-source.zip" -d extracted 2>"$ERRF" )
  rc=$?
  # symlink error 属已知良性现象：只计数、不判定（见 docs/LESSONS.md 第 4 条）
  if [ -f "$ERRF" ]; then
    n=$(grep -c 'symlink error' "$ERRF" 2>/dev/null || true)
    echo "INFO unzip stderr 行数=$(wc -l < "$ERRF" | tr -d ' ')，其中 symlink error=${n:-0}（良性，不参与判定）"
  fi
  [ "$rc" = "0" ] || { echo "RESULT tag=${TAG} status=FAIL stage=unzip rc=${rc}"; exit 1; }
fi

echo "== [4/4] 硬指标复核 =="
bash "$HERE/verify_tag.sh" "$TAG" "$ROOT"
