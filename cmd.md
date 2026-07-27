# Command Reference

> 项目常用命令与用户侧验证入口。命令应可直接复制执行。

## 常用命令

## RECAP / STEAM 最小可行性验证

默认 MVP 使用 seed 0、官方 30 条 SFT 轨迹和 64 条离线 rollout。资产与输出均位于
``/mnt/data/atticux/rlinf/``；它只用于验证代码链路和效果趋势，不作为论文级无泄漏对比。
运行时会自动把 1.4 GB 数据集复制到 ``$HOME/.cache/rlinf/datasets/`` 以避免 OSS
随机视频读取过慢；模型、checkpoint、sidecar 和评测结果仍持久化到 ``/mnt/data``。

### 1. 下载 MVP 资产

只下载 ``libero10_task0_sft``、``libero10_task0_eval`` 和所需模型，不下载
4,096-rollout 全集。

```bash
cd /root/RLinf
hf auth whoami
wandb status
bash examples/offline_rl/run_libero10_task0_comparison.sh prepare
```

RECAP/STEAM 后续训练与评测默认同时记录 TensorBoard 和 W&B，W&B 项目名为
``rlinf``。运行前应确保 ``wandb status`` 显示已登录。

### 2. 分阶段运行

```bash
# 原始 π₀.₅ SFT baseline：100 回合
bash examples/offline_rl/run_libero10_task0_comparison.sh baseline

# RECAP：1,000-step value + 200-step CFG
bash examples/offline_rl/run_libero10_task0_comparison.sh recap 0
bash examples/offline_rl/run_libero10_task0_comparison.sh eval recap 0

# STEAM：100-step ensemble value + 200-step CFG
bash examples/offline_rl/run_libero10_task0_comparison.sh steam 0
bash examples/offline_rl/run_libero10_task0_comparison.sh eval steam 0

bash examples/offline_rl/run_libero10_task0_comparison.sh summarize
```

### 3. 一次运行完整 MVP

长实验统一放进 tmux，避免 SSH、Codex 或终端会话结束时中断：

```bash
tmux new-session -d -s rlinf-recap-steam \
  'cd /root/RLinf && bash examples/offline_rl/run_libero10_task0_comparison.sh mvp 2>&1 | tee /tmp/rlinf-recap-steam.log'

# 重新接入；按 Ctrl-b d 可退出但保持任务运行
tmux attach-session -t rlinf-recap-steam

# 不接入，只查看最近 80 行
tmux capture-pane -pt rlinf-recap-steam -S -80
```

如果 RECAP 已完成，只需继续 RECAP 评测、STEAM 与汇总：

```bash
tmux new-session -d -s rlinf-recap-steam \
  'cd /root/RLinf && bash examples/offline_rl/run_libero10_task0_comparison.sh continue-mvp 2>&1 | tee /tmp/rlinf-recap-steam.log'
```

汇总结果写入
``/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-mvp/summary.json``，
包含成功率、相对 baseline 的百分点变化和 Wilson 95% 区间。

在 4 张 H20、资产已缓存的当前机器上，完整 MVP 串行复跑约需 4–6 小时：
baseline 约 10 分钟，RECAP 约 2–3 小时，STEAM 约 1–1.5 小时。首次下载资产另计。

本次 seed 0 实测结果如下：

| 方法 | success_once | 相对 baseline | Wilson 95% CI |
|---|---:|---:|---:|
| SFT baseline | 32/100 | — | [23.67%, 41.66%] |
| RECAP MVP | 9/100 | -23 pp | [4.81%, 16.23%] |
| STEAM MVP | 14/100 | -18 pp | [8.53%, 22.14%] |

两条方法均通过 value/advantage/CFG/eval 全链路验证，STEAM 比同等 CFG 步数的
RECAP 高 5 pp；但二者都未超过 SFT baseline。该结果只证明代码与迁移链路可用，
不能证明 100/1,000-step value + 200-step CFG 已获得算法收益。

## RECAP / STEAM 中等预算实验

中等实验使用 256 条确定性分层抽样 rollout、单 seed，并评测 CFG step
500/1,000。完整方案和运行结果统一维护在 ``docs/experiment-log.md``。

```bash
cd /root/RLinf

# 下载轻量元数据，生成抽样清单，只下载选中的 parquet 和双相机视频。
bash examples/offline_rl/run_libero10_task0_comparison.sh prepare-medium

# 串行运行 baseline、RECAP、STEAM、4 个 checkpoint 评测与汇总。
tmux new-session -d -s rlinf-recap-steam-medium \
  'cd /root/RLinf && bash examples/offline_rl/run_libero10_task0_comparison.sh medium 2>&1 | tee /tmp/rlinf-recap-steam-medium.log'

tmux capture-pane -pt rlinf-recap-steam-medium -S -80
```

也可以分阶段幂等运行：

```bash
bash examples/offline_rl/run_libero10_task0_comparison.sh recap-medium 0
bash examples/offline_rl/run_libero10_task0_comparison.sh eval-medium recap 0 500
bash examples/offline_rl/run_libero10_task0_comparison.sh eval-medium recap 0 1000
bash examples/offline_rl/run_libero10_task0_comparison.sh steam-medium 0
bash examples/offline_rl/run_libero10_task0_comparison.sh eval-medium steam 0 500
bash examples/offline_rl/run_libero10_task0_comparison.sh eval-medium steam 0 1000
bash examples/offline_rl/run_libero10_task0_comparison.sh summarize-medium
```

### 4. 显式运行完整实验

下面的命令会下载约 87 GB 数据并运行三 seed 长训练，不属于默认 MVP：

```bash
bash examples/offline_rl/run_libero10_task0_comparison.sh prepare-full
bash examples/offline_rl/run_libero10_task0_comparison.sh full
```

## 待用户验证

- **Status:** Passed（2026-07-14，seed 0）
- **Purpose:** 验证 RECAP 与 STEAM 的离线标注、价值训练、CFG 和 LIBERO-10 Task 0 评测链路，并观察相对 SFT baseline 的方向性趋势。
- **Prerequisites:** ``/mnt/data`` 可写、4 张 H20 可见、OpenPI/LIBERO 环境可用，且 Hugging Face 已登录并接受 Gemma 模型许可。
- **Commands:** 已运行 ``prepare``、三组训练/评测与 ``summarize``；上述命令可幂等复跑。
- **Pass criteria:** 已满足。RECAP/STEAM 均生成 value 与 CFG checkpoint；sidecar 分别覆盖 8,005 条 SFT 与 25,493 条 rollout；三组评测各记录 ``eval/num_trajectories: 100``；``summary.json`` 包含全部方法、差值与 Wilson 区间。
- **Evidence:** ``/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-mvp/summary.json``，以及 ``seed-0/{baseline,recap,steam}/eval.log``。
