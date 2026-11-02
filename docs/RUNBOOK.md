# RUNBOOK · 手动运行一次完整流水线

> 活文档，随脚本同步维护。凡与 `scripts/verify_tag.sh` 冲突，**以脚本为准**（判据只有一份实现）。
> 面向**人工触发**：不需要定时任务，也不需要 AI 在旁边判断下一步。

适用对象：`deepseek-ai/deepseek-harness`（改 `config/target.env` 可换仓）。
环境：Windows + Git Bash（`curl` / `tar` / `unzip` / `find` 随 Git for Windows 安装）。

---

## 0. 首次准备（只做一次，约 1 分钟）

```bash
cp config/local.env.example config/local.env
# 编辑 config/local.env，把 DSH_ARCHIVE_ROOT 改成自己的归档目录
#   Git Bash 写法：DSH_ARCHIVE_ROOT="/d/deepseek harness GitHub"
```

`config/local.env` **已被 `.gitignore` 忽略**，不会入库，也不影响其他机器。
不想建这个文件也可以临时给环境变量：`DSH_ARCHIVE_ROOT="/d/..." bash scripts/run.sh`。

自检（不下载任何东西）：

```bash
bash scripts/run.sh --dry-run
```

能打印 `LOCAL_TAGS=` / `REMOTE_TAGS=` / `NEW_TAGS=` 就说明配置通了。

---

## 1. 运行

**Windows 最简：双击仓根目录的 `run.cmd`**（结束后窗口停住，便于看结果）。

命令行等价：

```bash
bash scripts/run.sh            # 检测 + 归档所有新增 tag
bash scripts/run.sh --dry-run  # 只看计划
bash scripts/run.sh --tag X    # 只处理某个 tag（修复/复核）
bash scripts/run.sh --yes      # 跳过确认
```

脚本固定五步，**不需要人干预**：

| 步 | 动作 | 失败会怎样 |
|---|---|---|
| 1/5 | 检测远端 release，与本地 `*-source.zip` 求差集 | API/网络失败 ⇒ **exit 3**（明确不是「无新增」） |
| 2/5 | 列出计划并确认 | 无新增 ⇒ 直接结束（exit 0） |
| 3/5 | 逐 tag **串行** 走 `archive_one.sh`（下载 zip → 下载 tar.gz → 解压 → 复核） | 单 tag 失败不影响后续 tag，最后汇总 |
| 4/5 | 打印汇总表（字节数、条目对账、失效链接、STATUS） | —— |
| 5/5 | 打印成功/失败计数与日志路径 | 有失败 ⇒ **exit 1** |

不要并行起多个 `run.sh`：并发会触发 `fork: Permission denied`（见 `docs/LESSONS.md` 第 2 条）。

---

## 2. 看结果

正常输出尾部：

```
[4/5] 汇总
TAG                           ZIP_BYTES    TGZ_BYTES            ITEMS  BROKEN STATUS
dsh-v0.2.1-rc.5                45743225     34818362   16339+14=16353       0 PASS

[5/5] 结果：成功 1 / 失败 0
日志：/d/deepseek harness GitHub/logs/run-20261102-195107.log
```

三个判据（`verify_tag.sh` 唯一实现，必须同时成立）：

| 判据 | 要求 |
|---|---|
| 归档完整性 | zip `unzip -tq` / tar.gz `tar -tzf` 均通过（**在临时目录副本上**） |
| 合计条目 | `find -type f` + `find -type l` == `unzip -Z1 … \| grep -v '/$' \| wc -l` |
| 失效链接 | `find -type l ! -exec test -e {} \;` == 0 |

> `symlink error: File exists` 是 Git Bash 的**良性** stderr，不参与判定。

---

## 3. 失败处置

| 现象 | 环节 | 处置 |
|---|---|---|
| exit 3 / `未解析到任何 tag` | 检测 | GitHub API 未认证限流（60 次/小时）⇒ 稍后重跑；**不要**当成「无新增」 |
| exit 2 / `归档根不存在` | 预检 | 改 `config/local.env`；Git Bash 用 `/d/...`，不要写 `D:\...` |
| `curl: (18) transfer closed` 且文件偏小 | 下载 | 脚本自动兜底 5 轮 × 4 源；仍失败则重跑（幂等） |
| `GIVEUP zip` / `GIVEUP tar.gz` | 下载 | codeload 与镜像全失败 ⇒ 检查网络后重跑同一条命令 |
| `条目数不符` | 复核 | 多为解压中断或 zip 截断：删 `extracted/<repo>-<TAG>` 重跑 `--tag <TAG>` |
| `存在失效符号链接` | 复核 | 目标盘不支持符号链接 ⇒ 换解压方式，**勿当成功** |
| 想重做某个 tag | 任意 | `bash scripts/run.sh --tag <TAG> --yes`（幂等，会重下/重解压/重验） |

---

## 4. 手工等价命令（排障用，不是日常路径）

```bash
bash scripts/check_new.sh                     # 只检测
bash scripts/archive_one.sh <TAG>             # 单 tag 全流程
bash scripts/verify_tag.sh <TAG>              # 只复核
cd "$DSH_ARCHIVE_ROOT" && unzip -q <TAG>-source.zip -d extracted   # 手工解压
```

日常只需 `run.sh` —— 上面的命令是它的内部步骤，用于定位问题。

---

## 5. 跑完自查（三条）

1. `[5/5] 结果：成功 n / 失败 0`；
2. `extracted/<repo>-<TAG>` 目录存在，且 `RESULT` 行 `status=PASS`；
3. 日志已落 `$DSH_ARCHIVE_ROOT/logs/run-<时间>.log`（出问题时要靠它回溯）。

---

## Windows Git Bash 三个注意事项

1. **`tar` 不认 `C:/...`**：会把 `C:` 当远程主机，报 `Cannot connect to C: resolve failed`。
   用 `/c/...` 形式；脚本内统一经 `lib.sh::tmp_root()` 归一化。
2. **目标盘上直接校验会假失败**：`cp` 到临时目录再验（脚本已内置）。
3. **`unzip` 的 `symlink error: File exists` 是良性**：Git Bash 重复建链时报，不参与判定。
