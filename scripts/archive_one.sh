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
  # v1.2.0 起改用 tar.gz 解压（根治跨机 symlink 缺失，见 docs/LESSONS.md 第 12 条）：
  #   - zip 里的符号链接条目，Info-ZIP unzip 在 Windows 上**无法物化**（每条报
  #     `symlink error: File exists` 后静默跳过）⇒ 解压树必缺 N 个条目，硬指标复核
  #     在「unzip 无 symlink 权限」的机器上**必然 FAIL** —— 权限只是表象，换机器照样复发；
  #   - MSYS `tar` 对同一批链接条目能确定性地物化（建真链；真链建不出时按运行时
  #     约定退化为内容拷贝）⇒ 无论哪台机器、什么权限，每个条目都被落到盘上，
  #     `文件数 + 链接数 == zip 条目数` 恒可满足；
  #   - zip 仍下载并做完整性校验（verify A）+ 充当条目数基准清单（verify B），
  #     只是**不再用它解压**。两份归档由 GitHub 从同一 commit 生成，成员清单已实测一致。
  ( cd "$ROOT" && tar -xzf "${TAG}-source.tar.gz" -C extracted 2>"$ERRF" )
  rc=$?
  if [ -f "$ERRF" ] && [ -s "$ERRF" ]; then
    echo "INFO tar stderr 行数=$(wc -l < "$ERRF" | tr -d ' ')（正常应为 0；非 0 请对照 docs/LESSONS.md 第 12 条处置）"
  fi
  [ "$rc" = "0" ] || { echo "RESULT tag=${TAG} status=FAIL stage=tar-extract rc=${rc}"; exit 1; }
fi

echo "== [4/4] 硬指标复核 =="
bash "$HERE/verify_tag.sh" "$TAG" "$ROOT"
