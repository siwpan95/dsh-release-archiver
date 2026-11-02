# automation/prompt.md —— 平台定时任务提示词（现役）

> **本文件是现役调度任务的唯一提示词来源**：WorkBuddy 上的「deepseek-harness release 源码归档」任务
> 每周一 00:00 执行，内容与本文**逐字一致**。改这里，就要同步改平台任务；反之亦然。
>
> 人工触发不走本文件：Windows 双击 `run.cmd`，或 `bash scripts/run.sh`。
>
> 因为 `run.sh` 已经把原来靠 AI 做的判断全部下沉成脚本行为（检测、串行下载、校验、解压、复核、汇总、退出码），
> 提示词不再描述步骤，**只让执行者跑一条命令并如实转述结果**。调度器只负责「到点按一下」。

## 提示词正文（复制以下全部内容）

````text
【目标】把 github.com/deepseek-ai/deepseek-harness 的新 release 源码归档到 `/d/deepseek harness GitHub`（含 `extracted/` 解压与硬指标复核）。全部逻辑已固化在 `G:/repos/dsh-release-archiver` 仓内。本任务**只负责调用**，不再内联检测、下载、校验、解压等任何步骤。

【执行】只跑这一条命令（Git Bash，POSIX 路径）：
```
cd /g/repos/dsh-release-archiver && bash scripts/run.sh --yes
```

前置说明（脚本已自带，无需人工补做）：
- 配置读仓内 `config/local.env`（本机私有、已 gitignore）：`DSH_ARCHIVE_ROOT="/d/deepseek harness GitHub"`；优先级为 环境变量 > local.env > target.env。
- 流水线固定五步：检测新增 → 串行下载 zip + tar.gz → 临时目录副本完整性校验 → 解压到 `extracted/` → 硬指标复核（文件数 + 符号链接数 == zip 非目录条目数；失效链接为 0）。单 tag 失败不影响后续 tag。
- 日志自动写入 `$DSH_ARCHIVE_ROOT/logs/run-<时间>.log`，脚本结尾会打印日志路径。
- 退出码语义：0 = 成功（含「无新增」）；1 = 有 tag 失败；2 = 配置或环境问题；3 = 检测失败（网络 / GitHub API 限流 60 次每小时）。

【纪律】
- 退出码非 0 时**不得**报告成「无新增」；也**不要**自行改用其它下载方式（ghproxy、网页下载、工作区技能脚本等）重试或手工补步骤，只如实转述脚本输出的失败环节与其处置提示。
- 若 `cd` 失败或仓目录不存在（如 G: 盘未挂载），立即停止并报告该路径不可用；不要克隆、不要重建、不要改调别的脚本。
- 本任务只读检测 + 下载归档：不推送、不删除、不改动仓库结构与既有归档；多个 tag 必须由脚本串行处理，不要并行另跑。

【汇报】按以下五项，控制在 400 字以内：
1. 结论：无新增，或新增 N 个 tag（逐个列 tag 名）；
2. 汇总表关键行：`TAG / ZIP_BYTES / TGZ_BYTES / ITEMS（files+symlinks=entries）/ BROKEN / STATUS`；
3. 解压目录（仅 PASS）：`$DSH_ARCHIVE_ROOT/extracted/deepseek-harness-<TAG>`；
4. 失败环节（如有）：哪个 tag、哪一步、脚本给出的原因；
5. 日志路径。
````

## 换机器时要改的只有两处

| 位置 | 改什么 |
|---|---|
| 提示词里的 `cd /g/repos/...` | 本仓在该机的检出路径（Git Bash 写法） |
| 该机 `config/local.env` 的 `DSH_ARCHIVE_ROOT` | 该机归档根；**不必**改平台环境变量 |

## 为什么不把步骤写回提示词

| 关注点 | 落点 |
|---|---|
| 一条命令跑完全程 | `scripts/run.sh` |
| 判断有没有新增 | `scripts/check_new.sh`（API 失败 exit 3，不冒充「无新增」） |
| 两格式串行下载 | `scripts/archive_one.sh` + `scripts/dl_one.sh` |
| 硬指标复核 | `scripts/verify_tag.sh`（唯一实现） |
| 运行记录 | `$DSH_ARCHIVE_ROOT/logs/run-<时间>.log` |

提示词里每多写一句步骤，就多一份会与脚本漂移的副本 —— 判据只有一份实现，提示词只负责「调用 + 转述」。
