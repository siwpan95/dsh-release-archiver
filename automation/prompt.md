# automation/prompt.md —— 可直接粘回自动化平台的提示词

> **用途**：本仓是这条自动化的**权威描述**。平台上现役任务的提示词应与下面代码块**同源**；
> 若脚本判据变化，先改本仓再改平台提示词（判据只在脚本里实现，提示词只负责调脚本）。
> **调度**：周期由平台调度字段承载（当前为**每周**一次），**不要写进提示词正文**。

## 环境前提（平台侧一次性配置）

| 变量 | 含义 | 说明 |
|---|---|---|
| `DSH_ARCHIVE_ROOT` | 归档根（源码包与 `extracted/` 的父目录） | 各机不同，取值见 allin 事实源；**提示词与脚本都不写死** |
| `ARCHIVER_REPO` | 本仓在本机的检出路径 | 例：`<工作区>/repos/dsh-release-archiver` |

## 提示词正文

````text
每周检测 GitHub 仓库 deepseek-ai/deepseek-harness 的 releases；如有新增 tag，
把其源码归档下载到 $DSH_ARCHIVE_ROOT 并解压到 $DSH_ARCHIVE_ROOT/extracted。

全部动作通过本机检出仓 $ARCHIVER_REPO 的脚本完成（判据在脚本里，不要手写替代命令）：

0. 只读检测（不做任何下载）：
   bash scripts/weekly_check.sh
   - 输出 NEW_TAGS= 为空 ⇒ 结束，报告「无新增」。
   - 退出码非 0 ⇒ 明确区分「API/网络失败」，不得报告成「无新增」。

1. 对 NEW_TAGS 中每个 tag **串行**执行（一个 tag 一条命令，不要并行）：
   bash scripts/archive_one.sh <TAG>
   该脚本内含：zip 与 tar.gz 串行下载（codeload 直连优先、镜像兜底、唯一临时名、临时副本校验）、
   解压到 extracted/、以及硬指标复核。幂等，可安全重跑。

2. 复核硬指标（archive_one.sh 已调用；需要单独复跑时）：
   bash scripts/verify_tag.sh <TAG>
   必须同时满足：
   - find -type f 计数 + find -type l 计数 == zip 非目录条目数；
   - 失效符号链接数 == 0；
   - status=PASS。
   已知良性现象：解压时 stderr 出现 "symlink error: File exists" 属 Git Bash 正常行为，
   只要上述硬指标通过即判成功，勿误判失败。

3. 汇报：本次新增 tag、每个文件（文件名 + 字节数）、解压目录、复核数值
   （文件数 + 链接数 = 合计 vs zip 条目数、失效链接数）、以及失败环节（如有）。

约束：只读检测 + 下载归档 + 解压；不推送、不删除、不改仓库结构；下载与解压串行执行。
````

## 与平台现役任务的对应关系

| 平台提示词要点 | 本仓落点 |
|---|---|
| 先清点本地已有 tag | `scripts/weekly_check.sh` |
| 拉 release 列表并求差集 | 同上（含 API 失败与「无新增」的区分） |
| 两格式串行下载 | `scripts/archive_one.sh` + `scripts/dl_one.sh` |
| 落盘校验（临时副本） | `dl_one.sh` 内建 + `verify_tag.sh` 复跑 |
| 解压到 `extracted/` | `archive_one.sh` 第 3 步 |
| 硬指标复核 | `scripts/verify_tag.sh`（唯一实现） |
| 汇报格式 | `docs/RUNBOOK.md` 第 6 步模板 |
