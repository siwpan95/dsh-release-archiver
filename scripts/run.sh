#!/usr/bin/env bash
# 一键运行：检测 → 双格式下载 → 落盘校验 → 解压 → 硬指标复核 → 汇总。
#
# 面向**人工触发**：不需要定时任务、不需要 AI、不需要背命令。
# Windows 双击 run.cmd，或任一平台执行 `bash run.sh`；每次运行都完整走一遍流水线。
#
# 用法:
#   bash run.sh                 检测并归档所有新增 tag
#   bash run.sh --dry-run       只检测、只列计划，不下载任何文件
#   bash run.sh --tag <TAG>     只处理指定 tag（本地已有也重跑，幂等修复）
#   bash run.sh --yes           跳过确认（脚本调用 / 非交互场景）
#   bash run.sh -h              显示帮助
#
# 退出码: 0 成功（含「无新增」）/ 1 有 tag 失败 / 2 用法或环境问题 / 3 检测失败（网络或 API）
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
load_env "$HERE"

LOG=""

usage() {
  cat <<'EOF'
用法: bash run.sh [选项]

  （无选项）        检测上游 release，把本地缺失的 tag 全部归档（下载 + 校验 + 解压 + 复核）
  --dry-run         只检测并列出计划，不下载任何文件
  --tag <TAG>       只处理指定 tag（本地已有也重跑，用于修复）
  --yes, -y         跳过确认
  -h, --help        显示本帮助

第一次使用：复制 config/local.env.example 为 config/local.env，改一行 DSH_ARCHIVE_ROOT。
退出码: 0 成功 / 1 有 tag 失败 / 2 用法或环境 / 3 检测失败（网络或 API）
EOF
}

# 从 "RESULT tag=... files=... status=PASS" 里取字段
field() {
  printf '%s\n' "$1" | awk -v k="$2" '{
    for (i = 1; i <= NF; i++) {
      n = index($i, "=")
      if (n > 0 && substr($i, 1, n - 1) == k) { print substr($i, n + 1); exit }
    }
  }'
}

bytes_of() {
  if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else printf '%s' "-"; fi
}

main() {
  local tag_opt="" dry=0 assume_yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tag)
        [ $# -ge 2 ] || { echo "ERROR: --tag 需要一个 tag 值" >&2; return 2; }
        tag_opt="$2"; shift 2 ;;
      --tag=*) tag_opt="${1#*=}"; shift ;;
      --dry-run|-n) dry=1; shift ;;
      --yes|-y) assume_yes=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) echo "ERROR: 未知参数 $1" >&2; echo >&2; usage >&2; return 2 ;;
    esac
  done

  local ROOT="${DSH_ARCHIVE_ROOT:-}"
  local PROJ="${REPO##*/}"

  echo "=============================================================="
  echo " DSH 发布源码归档 · 手动运行"
  echo " 时间   $(date '+%Y-%m-%d %H:%M:%S')"
  echo " 目标   ${REPO}"
  echo " 归档根 ${ROOT:-<未配置>}"
  [ -n "$LOG" ] && echo " 日志   ${LOG}"
  echo "=============================================================="

  # ---- 0. 预检 ------------------------------------------------------------
  local miss=0 c
  for c in curl unzip tar find grep sed awk wc; do
    command -v "$c" >/dev/null 2>&1 || { echo "ERROR: 缺少命令: $c" >&2; miss=1; }
  done
  if [ "$miss" != 0 ]; then
    echo "提示：Windows 请用 Git for Windows 自带的 Git Bash 运行（上述命令随它安装）。" >&2
    return 2
  fi

  if [ -z "$ROOT" ]; then
    cat >&2 <<'EOF'
ERROR: 未配置归档根 DSH_ARCHIVE_ROOT。

只做一次：
  1) 复制 config/local.env.example 为 config/local.env
  2) 打开 config/local.env，把 DSH_ARCHIVE_ROOT 改成你的归档目录
     （Git Bash 写法，例如 /d/deepseek harness GitHub；不要写 D:\...）
  该文件已被 .gitignore 忽略，不会入库，也不影响其他机器。

临时使用：
  DSH_ARCHIVE_ROOT="/d/deepseek harness GitHub" bash run.sh
EOF
    return 2
  fi
  if [ ! -d "$ROOT" ]; then
    echo "ERROR: 归档根不存在: $ROOT" >&2
    echo "提示：改成实际存在的目录；Git Bash 用 /d/... 形式，不要用 D:\\ 形式。" >&2
    return 2
  fi
  if [ ! -w "$ROOT" ]; then
    echo "ERROR: 归档根不可写: $ROOT" >&2
    return 2
  fi
  mkdir -p "$ROOT/extracted" || { echo "ERROR: 无法创建 $ROOT/extracted" >&2; return 2; }

  local TMP
  TMP="$(tmp_root)/_dshrun.$$"
  mkdir -p "$TMP" || { echo "ERROR: 无法创建临时目录" >&2; return 2; }

  # ---- 1. 确定要处理的 tag ------------------------------------------------
  local NEW_TAGS="" LOCAL_N="?" REMOTE_N=""
  if [ -n "$tag_opt" ]; then
    echo
    echo "[1/5] 指定 tag：$tag_opt（跳过远端检测）"
    NEW_TAGS="$tag_opt"
    if [ -f "$ROOT/${tag_opt}-source.zip" ]; then
      echo "      本地已有该 tag 的归档 → 本次为幂等复核 / 修复"
    else
      echo "      本地无该 tag 的归档 → 将全新下载"
    fi
  else
    echo
    echo "[1/5] 检测新增 release ..."
    local cout="$TMP/check.out"
    bash "$HERE/check_new.sh" > "$cout" 2>&1
    local crc=$?
    sed 's/^/      /' "$cout"
    if [ "$crc" != 0 ]; then
      echo
      echo "ERROR: 检测失败（退出码 $crc）—— 这**不是**「无新增」：" >&2
      echo "       3 = GitHub API / 网络失败（未认证限流 60 次/小时），稍后重试；" >&2
      echo "       2 = 环境问题（归档根或配置）。" >&2
      return 3
    fi
    LOCAL_N="$(sed -n 's/^LOCAL_TAGS=//p' "$cout" | tail -1)"
    REMOTE_N="$(sed -n 's/^REMOTE_TAGS=//p' "$cout" | tail -1)"
    NEW_TAGS="$(sed -n 's/^NEW_TAGS=//p' "$cout" | tail -1)"
  fi

  if [ -z "$NEW_TAGS" ]; then
    echo
    echo "结果：**无新增**（本地已有 ${LOCAL_N} 个 tag，远端最近 ${REMOTE_N:-?} 个）。"
    echo "      未下载任何文件，本次结束。"
    return 0
  fi

  local n=0 t
  for t in $NEW_TAGS; do n=$((n + 1)); done

  echo
  echo "[2/5] 计划处理 ${n} 个 tag："
  local i=0
  for t in $NEW_TAGS; do
    i=$((i + 1))
    echo "      ${i}) ${t}"
  done

  if [ "$dry" = 1 ]; then
    echo
    echo "DRY-RUN：以上为计划，未下载任何文件。去掉 --dry-run 即可执行。"
    return 0
  fi

  if [ "$assume_yes" = 0 ]; then
    if [ -t 0 ]; then
      printf '\n继续下载并解压？[y/N] '
      local ans=""
      read -r ans || ans=""
      case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "已取消，未做任何改动。"; return 0 ;;
      esac
    else
      echo
      echo "非交互环境：自动继续（想先看计划请用 --dry-run）。"
    fi
  fi

  # ---- 2. 串行执行 --------------------------------------------------------
  echo
  echo "[3/5] 逐个 tag 执行流水线（串行；单 tag 失败不影响后续）"
  local results="$TMP/results.txt"
  : > "$results"
  local okn=0 failn=0
  i=0
  for t in $NEW_TAGS; do
    i=$((i + 1))
    echo
    echo "───── [${i}/${n}] ${t} ─────"
    local aout="$TMP/a.${i}.out"
    bash "$HERE/archive_one.sh" "$t" "$ROOT" 2>&1 | tee "$aout"
    local arc=${PIPESTATUS[0]}
    local res; res="$(grep '^RESULT ' "$aout" | tail -1)"
    local st="FAIL" f="-" l="-" e="-" b="-" v=""
    if [ -n "$res" ]; then
      # 缺字段时保留占位符（失败路径的 RESULT 不含 files/entries，别让默认值被空串覆盖）
      v="$(field "$res" status)";    [ -n "$v" ] && st="$v"
      v="$(field "$res" files)";     [ -n "$v" ] && f="$v"
      v="$(field "$res" symlinks)";  [ -n "$v" ] && l="$v"
      v="$(field "$res" entries)";   [ -n "$v" ] && e="$v"
      v="$(field "$res" broken)";    [ -n "$v" ] && b="$v"
    fi
    # 退出码与 RESULT 必须同时为成功，避免「打印 PASS 但退出非 0」被漏掉
    if [ "$arc" = 0 ] && [ "$st" = PASS ]; then
      okn=$((okn + 1))
    else
      failn=$((failn + 1))
      [ -n "$res" ] || st="FAIL(no-result)"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
      "$t" "$(bytes_of "$ROOT/${t}-source.zip")" "$(bytes_of "$ROOT/${t}-source.tar.gz")" \
      "$f" "$l" "$e" "$b" "$st" >> "$results"
  done

  # ---- 3. 汇总 ------------------------------------------------------------
  echo
  echo "[4/5] 汇总"
  printf '%-26s %12s %12s %16s %7s %s\n' "TAG" "ZIP_BYTES" "TGZ_BYTES" "ITEMS" "BROKEN" "STATUS"
  while IFS='|' read -r t zb tb f l e b st; do
    local items="${f}+${l}=${e}"
    [ "$f" = "-" ] && items="-"
    printf '%-26s %12s %12s %16s %7s %s\n' "$t" "$zb" "$tb" "$items" "$b" "$st"
  done < "$results"

  echo
  echo "解压目录（仅 PASS）："
  while IFS='|' read -r t _zb _tb _f _l _e _b st; do
    [ "$st" = PASS ] && echo "  $ROOT/extracted/${PROJ}-${t}"
  done < "$results"

  echo
  echo "[5/5] 结果：成功 ${okn} / 失败 ${failn}"
  [ -n "$LOG" ] && echo "日志：$LOG"
  if [ "$failn" != 0 ]; then
    echo "有 tag 失败 —— 见上方 FAIL 行与日志；脚本幂等，修复后重跑同一条命令即可。"
    return 1
  fi
  return 0
}

# ---- 日志：归档根/logs/run-<时间>.log（仓外，不入库） ----------------------
ROOT_PRE="${DSH_ARCHIVE_ROOT:-}"
if [ -n "$ROOT_PRE" ] && [ -d "$ROOT_PRE" ] && [ -w "$ROOT_PRE" ]; then
  if mkdir -p "$ROOT_PRE/logs" 2>/dev/null; then
    LOG="$ROOT_PRE/logs/run-$(date '+%Y%m%d-%H%M%S').log"
  fi
fi

if [ -n "$LOG" ]; then
  main "$@" 2>&1 | tee "$LOG"
  rc=${PIPESTATUS[0]}
else
  main "$@"
  rc=$?
fi
exit "$rc"
