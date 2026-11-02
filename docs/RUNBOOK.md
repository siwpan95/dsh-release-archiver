# RUNBOOK · 每周发布归档六步

> 活文档，随脚本同步维护。凡与 `scripts/verify_tag.sh` 冲突，**以脚本为准**（判据只有一份实现）。

适用对象：`deepseek-ai/deepseek-harness`（`config/target.env` 可换仓）。
环境：Windows + Git Bash（`tar`/`unzip`/`find` 均为 Git for Windows 自带版本）。

## 0. 准备

```bash
export DSH_ARCHIVE_ROOT="/deepseek harness GitHub"   # 去符盘写法；实际值见各机事实源
cd <本仓>/..
```

归档根下应已有：`<TAG>-source.zip` / `<TAG>-source.tar.gz` 成对文件 + `extracted/` 目录。

## 1. 只读检测

```bash
bash scripts/weekly_check.sh
```

判据：`NEW_TAGS=` 为空 ⇒ 本次无新增，直接收尾（**不做任何下载**）。

## 2. 逐 tag 全流程（**串行**，一个 tag 一条命令）

```bash
bash scripts/archive_one.sh dsh-v0.2.1-rc.5
```

不要并行起多个后台任务：并发进程会触发 `fork: Permission denied`，把重试链整条打断。

## 3. 落盘校验

已内建在第 2 步：`dl_one.sh` 下载时会先 `cp` 到临时目录再 `unzip -tq` / `tar -tzf`。
人工复核用：

```bash
bash scripts/verify_tag.sh dsh-v0.2.1-rc.5
```

## 4. 解压

已内建在第 2 步。手工等价命令：

```bash
cd "$DSH_ARCHIVE_ROOT"
unzip -q dsh-v0.2.1-rc.5-source.zip -d extracted
```

顶层目录名固定为 `<repo>-<TAG>`（例：`deepseek-harness-dsh-v0.2.1-rc.5`），
与 `extracted/` 下既有目录命名一致。

## 5. 硬指标复核

```bash
bash scripts/verify_tag.sh dsh-v0.2.1-rc.5
```

必须同时满足：

| 判据 | 要求 |
|---|---|
| 归档完整性 | zip `unzip -tq` / tar.gz `tar -tzf` 均通过（临时副本上） |
| 合计条目 | `find -type f` + `find -type l` == `unzip -Z1 … \| grep -v '/$' \| wc -l` |
| 失效链接 | `find -type l ! -exec test -e {} \;` == 0 |

## 6. 汇报

模板：

```
新增 tag：<TAG>（本地 <n> → <n+1>）
下载：<TAG>-source.zip <字节>（PASS）／<TAG>-source.tar.gz <字节>（PASS）
解压：extracted/<repo>-<TAG>
复核：files=<x> + symlinks=<y> = <x+y> vs zip 条目 <e>；失效链接 0；status=PASS
失败环节：无 / <stage>
```

## Windows Git Bash 三个注意事项

1. **`tar` 不认 `C:/...`**：会把 `C:` 当远程主机，报 `Cannot connect to C: resolve failed`。
   需要显式路径时用 `/c/...` 形式；脚本内一律用 `${TMPDIR:-/tmp}`。
2. **目标盘上直接校验会假失败**：`cp` 到临时目录再验（脚本已内置）。
3. **`unzip` 的 `symlink error: File exists` 是良性**：Git Bash 重复建链时报，不参与判定。

## 常见失败与处置

| 现象 | 环节 | 处置 |
|---|---|---|
| `curl: (18) transfer closed` 且文件明显偏小 | 下载 | 换下一个 URL（脚本自动兜底 5 轮 × 4 源）；镜像不支持续传，只能整包重下 |
| `GIVEUP zip` / `GIVEUP tar.gz` | 下载 | codeload 与三个镜像全失败 ⇒ 记「下载失败」，下次重跑（脚本幂等） |
| `条目数不符` | 复核 | 通常是解压被中断或 zip 截断：删掉 `extracted/<repo>-<TAG>` 重解，仍不符则重下 zip |
| `存在失效符号链接` | 复核 | 目标盘不支持符号链接或解压器降级为普通文件 ⇒ 换解压方式，勿当成功 |
| `未解析到任何 tag` | 检测 | GitHub API 限流（60 次/小时/未认证）⇒ 稍后重试，**不要**当成「无新增」 |
