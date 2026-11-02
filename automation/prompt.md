# automation/prompt.md ——【可选】接平台定时任务时的提示词

> **默认运行方式是人工触发**（Windows 双击 `run.cmd`，或 `bash scripts/run.sh`）。
> 本文件只在「仍然想让平台定时跑」时使用；不接定时任务可以完全忽略。
>
> 因为 `run.sh` 已经把原来靠 AI 做的判断全部下沉成脚本行为（检测、串行下载、校验、解压、复核、汇总、退出码），
> 提示词不再需要描述步骤，**只需让执行者跑一条命令并如实转述结果**。

## 环境前提

| 变量 | 含义 | 说明 |
|---|---|---|
| `ARCHIVER_REPO` | 本仓在本机的检出路径 | 例：`<工作区>/repos/dsh-release-archiver` |
| `DSH_ARCHIVE_ROOT` | 归档根 | 可写在 `config/local.env`（推荐），不必进平台环境变量 |

## 提示词正文

````text
在 $ARCHIVER_REPO 目录执行：

  bash scripts/run.sh --yes

要求：
1. 只调这个脚本，不要自己拼 curl / unzip / tar 命令，也不要改脚本。
2. 把输出原样转述，至少包含 [4/5] 汇总表与 [5/5] 结果行、以及日志路径。
3. 退出码含义：0 = 成功（含「无新增」）；1 = 有 tag 失败；2 = 配置问题；3 = 检测失败（网络或 API）。
   退出码 3 绝不能说成「无新增」。
4. 失败时最多重跑一次（脚本幂等）；仍失败则报告失败环节，不要反复重试。
````

## 与手动入口的对应关系

| 关注点 | 落点 |
|---|---|
| 一条命令跑完全程 | `scripts/run.sh` |
| 判断有没有新增 | `scripts/check_new.sh`（API 失败 exit 3，不冒充无新增） |
| 两格式串行下载 | `scripts/archive_one.sh` + `scripts/dl_one.sh` |
| 硬指标复核 | `scripts/verify_tag.sh`（唯一实现） |
| 运行记录 | `$DSH_ARCHIVE_ROOT/logs/run-<时间>.log` |
