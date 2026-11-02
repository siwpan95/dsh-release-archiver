# dsh-release-archiver —— DeepSeek Harness 发布源码归档流水线

## 仓库角色定位（投资组合分级 ②）

> 本仓在 siwpan 投资组合中定级为 **② 精选旗舰/保留**，领域 **工具链/自动化**，定位 **发布归档**。
> **角色**：把「每周检测上游 release → 双格式源码归档 → 完整性校验 → 解压复核」固化为可版本化的脚本与判据。
> **维护策略**：② 保留 —— 维持但不扩张；脚本参数化，换目标仓只改 `config/target.env`，不改代码。
> 投资组合统一分级索引（多机可查）：[组合分级决策索引 · allin 事实源](https://gitee.com/siwpan/allin/blob/master/docs/事实源/组合分级决策索引.md)。

把一个**已经在无人值守跑着**的自动化流程，从「会话里的临时命令 + 记忆里的口头判据」变成**可复核的仓**：
判据写在脚本里、坑写在台账里、提示词写在 `automation/prompt.md` 里。

## 这个仓解决什么问题

上游 `deepseek-ai/deepseek-harness` 几乎每个版本只发 **GitHub 自动生成的源码归档**（`assets: 0`），
而下载这条路有四个反直觉的坑（见 [`docs/LESSONS.md`](docs/LESSONS.md)）：

1. 校验**不能在目标盘上做** —— 在 `D:`/`G:` 上跑 `tar -tzf` 会把完好文件判成损坏；
2. 下载**不能并行** —— 并发后台任务会触发 `fork: Permission denied`，把整条重试链打断；
3. `tar` **不认 `C:/...` 形式** —— 会当成远程主机并报 `Cannot connect to C: resolve failed`；
4. 解压**符号链接的 stderr 是良性的** —— `symlink error: File exists` 不代表失败，判据要看硬指标。

本仓把这四条变成**默认行为**，而不是每次重新记一遍。

## 快速开始

```bash
# 0) 归档根必须显式给出（仓内不写死盘符，见 allin SPEC-001 铁律 5）
export DSH_ARCHIVE_ROOT="/deepseek harness GitHub"   # 去符盘写法，实际值见各机事实源

# 1) 只读检测：本地缺哪些 tag
bash scripts/weekly_check.sh

# 2) 对每个新增 tag 走全流程（下载 → 校验 → 解压 → 硬指标复核）
bash scripts/archive_one.sh dsh-v0.2.1-rc.5

# 3) 只复核，不下载（对已归档的 tag 重跑判据）
bash scripts/verify_tag.sh dsh-v0.2.1-rc.5
```

`archive_one.sh` 结束时打印一行机器可读结果：

```
RESULT tag=dsh-v0.2.1-rc.5 files=16339 symlinks=14 entries=16353 broken=0 status=PASS
```

## 目录

```
config/target.env        目标仓库 / 分页 / 归档根（环境变量优先，不写死盘符）
scripts/lib.sh           共用工具：临时目录归一化（Windows 的 TMPDIR 是盘符形式，tar 不认）
scripts/dl_one.sh        单文件下载（codeload 直连优先 + 代理兜底 + 唯一临时名 + /tmp 副本校验）
scripts/archive_one.sh   单 tag 全流程编排（zip 与 tar.gz 串行，判据委托 verify_tag.sh）
scripts/weekly_check.sh  只读检测：本地 tag 集 vs releases?per_page=N 差集
scripts/verify_tag.sh    硬指标唯一实现（条目数 / 文件数 / 符号链接 / 失效链接 / 归档完整性）
docs/RUNBOOK.md          六步操作手册（含 Windows Git Bash 注意事项与报告格式）
docs/LESSONS.md          踩坑台账（每条附日期与实证）
automation/prompt.md     可直接粘回自动化平台的提示词（与现役任务同源）
```

## 六步流程（与 `automation/prompt.md` 一一对应）

| 步 | 动作 | 命令 | 判据 |
|---|---|---|---|
| 0 | 清点本地已有 tag | `ls "$DSH_ARCHIVE_ROOT"/*-source.zip` | 文件名形如 `<TAG>-source.zip`，**tag 带仓库前缀**（如 `dsh-`） |
| 1 | 拉远端 release 并求差集 | `bash scripts/weekly_check.sh` | 差集为空 ⇒ 「无新增」，到此结束 |
| 2 | 逐 tag 下载 zip / tar.gz | `bash scripts/archive_one.sh <TAG>` | 串行；单个脚本内两个扩展名顺序执行 |
| 3 | 落盘校验 | 脚本内 `verify_tag.sh` | **先 `cp` 到临时目录再校验**，目标盘上直接校验会假失败 |
| 4 | 解压 | `unzip -q <TAG>-source.zip -d extracted` | 顶层目录名 `<repo>-<TAG>`，与既有目录命名一致 |
| 5 | 硬指标复核 | `bash scripts/verify_tag.sh <TAG>` | 见下节 |
| 6 | 汇报 | —— | 新增 tag / 文件字节数 / 复核数值 / 失败环节（如有） |

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
