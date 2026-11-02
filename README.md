# dsh-release-archiver —— DeepSeek Harness 发布源码归档流水线

## 仓库角色定位（投资组合分级 ②）

> 本仓在 siwpan 投资组合中定级为 **② 精选旗舰/保留**，领域 **工具链/自动化**，定位 **发布归档**。
> **角色**：把「按需检测上游 release → 双格式源码归档 → 完整性校验 → 解压复核」固化为**一条命令**，人可独立跑完。
> **维护策略**：② 保留 —— 维持但不扩张；脚本参数化，换目标仓只改 `config/target.env`，不改代码。
> 投资组合统一分级索引（多机可查）：[组合分级决策索引 · allin 事实源](https://gitee.com/siwpan/allin/blob/master/docs/事实源/组合分级决策索引.md)。

把一条原本依赖平台定时任务 + AI 编排的流程，变成**独立项目**：判据写在脚本里、坑写在台账里、
入口只有一条命令 —— **不需要定时器，也不需要 AI 在旁边判断下一步做什么**。

## 为什么是手动触发（2026-11-02 定调）

原先是「每周自动跑」，因为那时它活在 WorkBuddy 的定时任务里：调度由平台推进，异常由 AI 现场判断。
一旦独立成仓，这两个前提都不成立 —— 人不在场时没人推进，AI 不在场时没人解读输出。
所以触发方式改为**人工按需**，并把「原来靠 AI 做的判断」全部下沉进脚本：

| 原来靠 AI / 平台 | 现在由脚本承担 |
|---|---|
| 到点触发 | 人运行 `run.sh`（Windows 双击 `run.cmd`） |
| 判断「有没有新增」 | `check_new.sh` 求差集，**API 失败明确 exit 3，不冒充「无新增」** |
| 决定下一步做什么 | `run.sh` 固定五步：检测 → 下载 → 校验 → 解压 → 复核 |
| 解读「这算成功吗」 | `verify_tag.sh` 给硬指标与 `status=PASS/FAIL`，退出码同步 |
| 记录这次干了什么 | 自动写 `$DSH_ARCHIVE_ROOT/logs/run-<时间>.log` |

代价是**必须有人记得去跑**；收益是**跑的人不需要懂这套坑** —— 命令、判据、失败处置都在仓里。

## 这个仓解决什么问题

上游 `deepseek-ai/deepseek-harness` 几乎每个版本只发 **GitHub 自动生成的源码归档**（`assets: 0`），
而下载这条路有四个反直觉的坑（见 [`docs/LESSONS.md`](docs/LESSONS.md)）：

1. 校验**不能在目标盘上做** —— 在 `D:`/`G:` 上跑 `tar -tzf` 会把完好文件判成损坏；
2. 下载**不能并行** —— 并发后台任务会触发 `fork: Permission denied`，把整条重试链打断；
3. `tar` **不认 `C:/...` 形式** —— 会当成远程主机并报 `Cannot connect to C: resolve failed`；
4. 解压**符号链接的 stderr 是良性的** —— `symlink error: File exists` 不代表失败，判据要看硬指标。

本仓把这四条变成**默认行为**，而不是每次重新记一遍。

## 快速开始（人工触发）

**Windows：双击 `run.cmd`** —— 打开控制台跑完整条流水线，结束停住等你按键。

**命令行：**

```bash
# 0) 只做一次：复制配置模板，改一行归档根（该文件已被 .gitignore 忽略）
cp config/local.env.example config/local.env
vi config/local.env          # DSH_ARCHIVE_ROOT="/d/deepseek harness GitHub"

# 1) 看计划，不下载
bash scripts/run.sh --dry-run

# 2) 正式跑：检测 → 下载 → 校验 → 解压 → 复核 → 汇总
bash scripts/run.sh

# 3) 只修复/复核某个 tag（本地已有也重跑，幂等）
bash scripts/run.sh --tag dsh-v0.2.1-rc.5
```

结束时打印汇总表与每个 tag 的 `RESULT` 行：

```
TAG                           ZIP_BYTES    TGZ_BYTES            ITEMS  BROKEN STATUS
dsh-v0.2.1-rc.5                45743225     34818362   16339+14=16353       0 PASS

RESULT tag=dsh-v0.2.1-rc.5 files=16339 symlinks=14 entries=16353 broken=0 status=PASS
```

退出码：`0` 成功（含无新增）／`1` 有 tag 失败／`2` 用法或环境／`3` 检测失败（网络或 API）。
每次运行的完整输出另存 `$DSH_ARCHIVE_ROOT/logs/run-<时间>.log`。

## 目录

```
run.cmd                   Windows 双击入口（调 run.sh，结束后暂停）
config/target.env        目标仓库 / 分页（环境变量优先，不写死盘符）
config/local.env.example 本机私有配置模板（复制为 local.env；后者已被忽略）
scripts/lib.sh           共用：临时目录归一化 + 配置加载（local.env → target.env）
scripts/run.sh           一键入口：检测 → 下载 → 校验 → 解压 → 复核 → 汇总 + 日志
scripts/dl_one.sh        单文件下载（codeload 直连优先 + 代理兜底 + 唯一临时名 + /tmp 副本校验）
scripts/archive_one.sh   单 tag 全流程编排（zip 与 tar.gz 串行，判据委托 verify_tag.sh）
scripts/check_new.sh     只读检测：本地 tag 集 vs releases?per_page=N 差集
scripts/verify_tag.sh    硬指标唯一实现（条目数 / 文件数 / 符号链接 / 失效链接 / 归档完整性）
docs/RUNBOOK.md          人工运行手册（失败处置 + 手工等价命令）
docs/LESSONS.md          踩坑台账（11 条，每条附日期与实证）
automation/prompt.md     【可选】仍要接平台定时任务时的提示词（与手动入口同源）
```

## 一次运行的五步（`run.sh` 内部顺序）

| 步 | 动作 | 落点 | 判据 |
|---|---|---|---|
| 0 | 预检：命令、归档根、可写性 | `run.sh` 开头 | 缺任何一项立刻退出（exit 2），不猜默认值 |
| 1 | 检测新增 tag | `check_new.sh` | 差集为空 ⇒ 「无新增」，**不做任何下载**；API 失败 ⇒ exit 3 |
| 2 | 逐 tag 下载 zip / tar.gz | `archive_one.sh` → `dl_one.sh` | **串行**，一个 tag 内两种扩展名顺序执行 |
| 3 | 落盘校验 | `dl_one.sh` 内建 | **先 `cp` 到临时目录再 `unzip -tq` / `tar -tzf`**，目标盘上直接校验会假失败 |
| 4 | 解压 | `archive_one.sh` | `unzip -q <TAG>-source.zip -d extracted`，顶层目录 `<repo>-<TAG>` |
| 5 | 硬指标复核 + 汇总 | `verify_tag.sh` → `run.sh` | 见下节；`run.sh` 输出表格与 `RESULT` 行，并写日志 |

## 校验判据（唯一实现：`scripts/verify_tag.sh`）

| 判据 | 阈值 | 为什么 |
|---|---|---|
| 归档完整性 | `unzip -tq` / `tar -tzf` 均通过（**在临时目录副本上**） | 目标盘校验会假失败；截断包必须当场拦下 |
| **合计条目** | `find -type f` + `find -type l` **== `unzip -Z1 … \| grep -v '/$'` 计数** | 唯一能证明「没漏解压」的等式 |
| **失效链接** | `find -type l ! -exec test -e {} \;` **== 0** | 符号链接跨平台解压最常见的静默损坏 |
| 解压退出码 | `0` | 非 0 即失败，不看 stderr 是否"看起来还好" |

> **`symlink error: File exists` 属已知良性现象**（Git Bash 的 unzip 重复创建链接时报），
> 判定只看上面两条硬指标 —— 这是本仓刻意写进脚本的原因：**只看 stderr 会误判成功为失败**。

## 已知坑（摘要，完整版见 `docs/LESSONS.md`）

| # | 坑 | 表现 | 处置 |
|---|---|---|---|
| 1 | 目标盘上直接校验 | 完好包被判「损坏」 | `cp` 到临时目录再校验 |
| 2 | 并行下载 | `fork: Permission denied`，整条链死 | 串行，一个 bash 里顺序跑 |
| 3 | `tar` 遇 `C:/...` | `Cannot connect to C: resolve failed` | 用 Git Bash 的 `/c/...` 形式 |
| 4 | 代理镜像截断大文件 | `curl: (18) transfer closed`，且不支持 Range | codeload 直连优先，代理仅兜底 |
| 5 | `rm` 清理临时文件挂起 | 重试链卡死 | 每次用唯一临时名，不 `rm` |
| 6 | 目录名与 tag 混淆 | 查 API 404 | 区分 release **名** 与 **tag**（tag 带前缀） |
| 7 | `${TMPDIR:-/tmp}` 在 Windows 上是盘符形式 | 临时目录校验假失败（`tar` 把 `C:` 当远程主机） | `scripts/lib.sh` 的 `tmp_root()` 归一化；见 `docs/LESSONS.md` 第 10 条 |

## 借鉴记账

| 项 | 内容 |
|---|---|
| 来源 | 本工作区自建技能 `github-release-source-archive-download`（`~/.workbuddy/skills/`），`agent_created: true` |
| 许可 | MIT（本工作区自有产物，与 allin 铁律 0 一致） |
| 借用范围 | `scripts/dl_one.sh` **逐字沿用**该技能的下载脚本（仅补来源注记）；`docs/LESSONS.md` 的坑位来自该技能 SKILL.md 与本仓 2026-10-29 / 10-30 / 11-02 三次实跑记录 |
| 不入仓声明 | **归档本体不入库**：`*-source.zip` / `*-source.tar.gz` 与 `extracted/` 一律由 `.gitignore` 挡在库外（仓位卫生 H4 亦禁止提交压缩包） |

## 许可

MIT，见 [LICENSE](LICENSE)。
