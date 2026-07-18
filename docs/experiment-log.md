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

- **状态：** 完成。RECAP 与 STEAM 均已完成 value → advantage → CFG →
  100 回合评测 → 汇总的完整链路；评测结果、checkpoint 与日志均已落在 OSS。
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
- **最终结果：** 汇总以 ``success_once`` 为主指标，结果如下（单 seed、每组
  100 回合；Wilson 95% CI 见 ``summary.json``）：

  | 方法 | success_once | 相对 SFT baseline |
  | --- | ---: | ---: |
  | SFT baseline | 35% | — |
  | RECAP step 500 | 42% | +7 pp |
  | RECAP step 1,000 | **60%** | **+25 pp** |
  | STEAM step 500 | 55% | +20 pp |
  | STEAM step 1,000 | 52% | +17 pp |

  STEAM step 500 的 ``success_at_end/success_once`` 均为 55%；step 1,000
  分别为 50%/52%。RECAP 的 step 500 为 42%/42%，step 1,000 为 58%/60%
  （前者为 at-end，后者为 once）。
- **日志与产物：** W&B 项目 ``atticux/rlinf``；本地根目录
  ``/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-medium``。
- **运行证据：** W&B 项目 ``atticux/rlinf``；baseline run
  ``https://wandb.ai/atticux/rlinf/runs/v2o8m2zm``，RECAP value run
  ``https://wandb.ai/atticux/rlinf/runs/91a7zyrh``，STEAM step 500 eval run
  ``https://wandb.ai/atticux/rlinf/runs/dgzdnm67``，STEAM step 1,000 eval run
  ``https://wandb.ai/atticux/rlinf/runs/6b15twrk``。统一结果为
  ``/mnt/data/atticux/rlinf/experiments/recap-steam-libero10-task0-medium/summary.json``；
  两份 STEAM eval 日志位于同一实验目录的 ``seed-0/steam_step{500,1000}/eval.log``。
- **运行异常：** 首次运行于 11:22 因 ``libero10_task0_eval`` 缺少同 tag
  returns sidecar 退出；提交 ``450e9272`` 补齐 returns 配置和回归测试，实际
  生成 25,493-row sidecar 后续跑。baseline 产物被保留，没有重复评测。第二次
  运行于 21:26 在 STEAM advantage 的 local rank 3 收到 ``SIGSEGV``（exit
  code -11）；elastic launcher 终止其余三个 rank。该失败发生在数据读取前；
  单卡探针已越过初始化，正式续跑改为 ``CUDA_VISIBLE_DEVICES=0,1,2``、
  ``RLINF_NPROC=3``，复用 STEAM value checkpoint 并避开物理 GPU 3。
- **迁移与恢复：** 三卡 advantage 已完成并写入两份 sidecar；原四卡 CFG 在
  step 514 为服务器迁移主动停止。新机器以两张 H20 从 ``global_step_500``
  的 full weights 恢复，完成 step 1,000（训练阶段约 2 小时 56 分）。新机缺少
  TorchCodec 所需的 ``libpython3.11.so.1.0`` 动态库路径，设置
  ``LD_LIBRARY_PATH=/root/miniconda3/envs/dsrl_pi0/lib:${LD_LIBRARY_PATH:-}``
  后恢复正常；不影响已保存的 checkpoint。
- **归档：** 续跑中断日志与原始 SIGSEGV 日志已复制到
  ``seed-0/steam/run-logs/``；W&B 本地同步目录也在同一 OSS 实验根目录下。
- **工程验收：** 256 条子集、returns/advantages sidecar、两种 CFG
  checkpoint、5 组完整评测和 ``summary.json`` 均已存在；评测完成时训练与评测
  进程均已退出、GPU 已释放。
- **结论与边界：** 两种方法均超过 SFT baseline，证明当前 Medium 配置的实现
  和方向性收益成立。RECAP 在 500→1,000 steps 持续提升；STEAM 在 step 500
  取得峰值、继续训练后下降 3 pp，因此后续比较应保留 STEAM step 500 checkpoint。
  这是单任务、单 seed 的最小可行性验证，不可作为论文级别的统计结论；不自动扩展
  到 full，等待真机迁移或新增 benchmark 的具体计划。

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
