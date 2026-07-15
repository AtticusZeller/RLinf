# 实验日志

> 本文档记录真实实验的方案、运行状态、产物和结论。开发任务完成情况见
> ``docs/log.md``；这里不把“代码跑通”写成“算法有效”。最新实验在最上面。

## 记录规范

每个实验必须记录以下信息：

- **目标与假设：** 本次实验要回答的问题，以及判定方向性收益的标准。
- **数据与配置：** 数据版本、抽样方式、seed、训练步数和评测规模。
- **运行证据：** W&B 链接、日志、checkpoint、汇总文件和实际耗时。
- **结果与结论：** 成功率、相对 baseline、异常和下一步；未完成时明确标记状态。

## 2026-07-15 · RECAP / STEAM · LIBERO-10 Task 0 Medium

- **状态：** 运行中；2026-07-15 11:07（UTC+8）启动，当前处于 baseline
  评测阶段。
- **目标与假设：** 判断 MVP 的负收益主要来自 64 条 rollout 与 200-step CFG
  预算不足，还是当前方法/数据组合本身没有方向性收益。
- **数据：** 30 条官方 SFT；从 4,096 条 rollout 按 ``is_success`` 分层、
  seed 0 确定性抽取 256 条。清单写入数据集
  ``meta/subset_manifest.json``，不得手工替换。
- **资产准备结果：** 实际抽到 125 条成功、131 条失败，共 97,338 frames、
  256 个 parquet 和 512 个双相机视频；持久化体积 5.0 GB。LeRobot 元数据
  已成功识别 256 episodes、10 FPS；源数据仍为兼容的 LeRobot 2.0 stats 格式。
- **训练：** RECAP value 2,000 steps；STEAM ensemble value 500 steps；两者
  CFG 均为 1,000 steps，并在 step 500/1,000 保存 checkpoint。
- **评测：** 单 seed；baseline、RECAP step 500/1,000、STEAM step 500/1,000
  各运行 100 回合固定初始状态评测。
- **日志与产物：** W&B 项目 ``atticux/rlinf``；本地根目录
  ``/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-medium``。
- **启动证据：** tmux 会话 ``rlinf-recap-steam-medium``；统一日志
  ``/tmp/rlinf-recap-steam-medium.log``；baseline W&B run
  ``https://wandb.ai/atticux/rlinf/runs/v2o8m2zm``。
- **工程通过标准：** 256 条子集、returns/advantages sidecar、value/CFG
  checkpoint、5 组完整评测和 ``summary.json`` 全部存在。
- **方向性判断：** 先比较 step 500→1,000，再比较 SFT baseline 32%。若
  RECAP 与 STEAM 都未超过 baseline，且随 CFG 步数没有上升，则停止扩到 full。
- **预计成本：** 4 张 H20、资产已缓存后约 12–16 小时；选中数据下载约
  3 分钟，物化约 3 分钟。训练与评测实际耗时在完成后回填。

## 2026-07-14 · RECAP / STEAM · LIBERO-10 Task 0 MVP

- **状态：** 完成。
- **方案：** seed 0；30 条 SFT + 64 条 rollout；RECAP value 1,000 steps；
  STEAM value 100 steps；两者 CFG 200 steps；每种方法评测 100 回合。
- **结果：** SFT baseline 32%；RECAP 9%（-23 pp）；STEAM 14%（-18 pp）。
- **耗时：** 约 5 小时；RECAP value 约 88 分钟，两组 CFG 各约 39 分钟。
- **证据：**
  ``/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-mvp/summary.json``。
- **结论：** 两条 value → advantage → CFG → eval 工程链路成立；该预算下
  没有获得算法收益，不能据此进入 full。

## 2026-07-14 至 2026-07-15 · DSRL Pi0 · LIBERO

- **状态：** 完成，作为历史实验保留，不再作为当前主 baseline。
- **方案：** Pixel SAC，500,000 steps，seed 0，10 回合定期评测。
- **结果：** 最终日志中的最近一次 10 回合评测为 10/10，最终 rollout 成功；
  总运行时长 18:51:42。
- **W&B：**
  ``https://wandb.ai/atticux/DSRL_pi0_Libero/runs/dsrl_pi0_libero_2026_07_14_15_20_44_0000--s-0``。
- **日志：**
  ``/mnt/data/atticux/dsrl_pi0/logs/DSRL_pi0_Libero/launcher-20260714-152037.log``。
- **异常：** 退出时出现 EGL context 销毁异常；它发生在训练和 W&B 收尾后，
  不影响 500k steps 完成，但不应把单次 10/10 视为跨 seed 结论。
