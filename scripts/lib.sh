#!/usr/bin/env bash
# 共用小工具：临时目录解析。
#
# 为什么需要它（2026-11-02 实测）：Windows 上 `TMPDIR` **本身**就是盘符形式
# （`C:\Users\<user>\AppData\Local\Temp`），所以 `${TMPDIR:-/tmp}` 这种「有就用、没有才退」
# 的写法在这里**永远退不到 `/tmp`**，拿到的是 `C:\...`。
# 而 `tar` 会把 `C:` 当远程主机（`Cannot connect to C: resolve failed`），
# 于是「在临时目录副本上校验」这条纪律会以最讽刺的方式失效：**临时目录本身不可用**。
#
# 处置：统一经 `tmp_root()` 取临时目录 —— 有 cygpath 就转成 POSIX 形式（`/c/...`），
# 转不了或本来就不是 POSIX 路径则退到 `/tmp`。所有脚本只用这一个入口。

tmp_root() {
  local t="${TMPDIR:-/tmp}"
  if command -v cygpath >/dev/null 2>&1; then
    t="$(cygpath -u "$t" 2>/dev/null || printf '%s' /tmp)"
  fi
  case "$t" in
    /*) printf '%s\n' "$t" ;;
    *)  printf '%s\n' /tmp ;;
  esac
}

# load_env <脚本所在目录>
# 配置加载顺序（后者不覆盖前者已显式给出的值）：
#   1. 调用者环境变量（最高优先，`REPO=owner/repo bash run.sh` 可临时覆盖）
#   2. config/local.env —— 本机私有，**已被 .gitignore 忽略**，存放归档根等带盘符路径
#   3. config/target.env —— 仓内默认值，不含任何盘符
#
# 为什么要有 local.env（2026-11-02）：人工触发要求「不改环境变量也能跑」。Windows 上
# 让普通用户去设 setx 是把简单事做复杂；改为复制一个 example、改一行即可。
load_env() {
  local here="$1"
  if [ -f "$here/../config/local.env" ]; then
    # shellcheck source=../config/local.env
    . "$here/../config/local.env"
  fi
  # shellcheck source=../config/target.env
  . "$here/../config/target.env"
}
