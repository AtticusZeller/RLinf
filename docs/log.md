# Development Log

> 已验证完成的任务记录。最新的在最上面。

<!-- 每个任务通过全部必要验证后，在本行下方追加一条 -->

## 2026-07-23 · RLT ManiSkill W&B 实验状态核验

- 已核验 W&B 项目 ``atticux/rlt-maniskill`` 的 6 个 run。正式 SFT 初始化
  ``stage1-full``（``j1fn4s84``）状态为 ``finished``，完成 1,999/2,000 step；
  最后 ``train/loss`` 为 0.5497、``train/rlt_loss`` 为 0.5407、
  ``train/vla_loss`` 为 0.00894。
- ``stage2-smoke``（``psqd2ti0``）已正常完成 2/2 step，验证了 ManiSkill
  rollout 流程；但 return、reward 和 ``success_once`` 均为 0，replay transition
  数、actor/critic update 数和 ``update_step`` 均为 0，尚未达到在线 RLT 更新条件。
- 当前 W&B 未发现 ``stage2-full`` run；其余 3 个 ``stage2-smoke`` run 没有有效
  summary。结论是 stage 1 已完成，stage 2 仅完成 smoke 流程验证，尚未产出正式
  在线 RLT 训练结果。

## 2026-07-18 · 完成 RECAP / STEAM Medium 实验评估

- STEAM 从 OSS 的 ``global_step_500`` 恢复到 step 1,000，并完成 step 500/1,000
  两组各 100 回合的 LIBERO-10 Task 0 评测；``summary.json`` 已在 OSS 生成。
- 汇总的 ``success_once`` 为：SFT baseline 35%、RECAP step 500 42%、RECAP
  step 1,000 60%、STEAM step 500 55%、STEAM step 1,000 52%。两种方法均在
  此单任务单 seed MVP 中超过 SFT；STEAM 的较优 checkpoint 为 step 500。
- 已核验评测完成时训练/评测进程全部退出、GPU 资源释放，以及 5 组评测汇总、
  OSS checkpoint 和 eval 日志均存在。完整实验记录见 ``docs/experiment-log.md``。

## 2026-07-16 · STEAM Medium 迁移前安全暂停

- 已在 STEAM CFG ``global_step_500`` 后主动停止训练；确认所有 GPU 进程、
  自动评测 watcher 均已退出。
- 已在 OSS 核验 STEAM value、两份 advantage sidecar、step 500 full weights、
  4 个分布式 checkpoint shard、W&B 目录与续跑/SIGSEGV 归档日志。
- 恢复入口为 ``global_step_500`` 的 ``runner.resume_dir``；恢复到 step 1,000
  后仍需运行 STEAM 两档 100 回合评测和 Medium 汇总。

## 2026-07-15 · 修复 Medium RECAP value 启动失败

- Medium returns 配置补齐 ``libero10_task0_eval``，确保 value validation
  使用同 tag 的 returns sidecar；新增配置关系回归测试。
- 已通过 Ruff、6 个 pytest、Hydra 组合检查，并真实生成 25,493-row eval
  returns sidecar，消除 4 个 FSDP worker 初始化时的 ``FileNotFoundError``。

## 2026-07-15 · RECAP / STEAM 中等预算实验入口

- 新增专有 ``docs/experiment-log.md``，分离实验假设、运行证据和算法结论；
  Medium 使用单 seed、256 条确定性分层 rollout、两档 CFG checkpoint 与
  5 组各 100 回合评测。
- 新增 LeRobot 子集工具、7 份 Medium YAML 和统一 launcher 子命令；重要
  数据、checkpoint 与汇总写入 ``/mnt/data/atticux/rlinf/``，训练默认同步
  TensorBoard 与 W&B。
- 真实准备并验证 5.0 GB 数据：125 条成功、131 条失败、97,338 frames、
  256 个 parquet、512 个视频；LeRobot 元数据可正常加载。
- 已通过 Ruff、5 个 pytest、7 份 YAML 解析、7 组 Hydra 组合、shell 语法、
  launcher 参数检查以及真实数据首尾重编号检查。

## 2026-07-15 · RECAP / STEAM 默认启用 W&B

- RECAP value、STEAM value、共享 CFG 与三份 LIBERO Task 0 评测配置默认同时启用 TensorBoard 和 W&B，统一写入 W&B 项目 ``rlinf``。
- 已验证六份 YAML 解析与 logger backend 值；当前 ``.venv`` 使用 W&B 0.25.0，认证信息已配置。

## 2026-07-14 · RECAP / STEAM · LIBERO-10 Task 0 MVP

- 退役 DSRL（Pi0 + LIBERO-Spatial）的 4 份训练配置、e2e/CI 入口与中英文活跃文档；保留底层通用实现和历史发布记录。
- 新增 YAML 驱动的 RECAP/STEAM full 与 MVP 配置、统一 launcher、三组 LIBERO 评测配置、Wilson 区间汇总器和单元测试；数据与重要产物持久化到 ``/mnt/data/atticux/rlinf/``。
- seed 0 真实跑通 value → advantage → CFG → 100 回合 eval：SFT baseline 32%、RECAP 9%、STEAM 14%。这验证了两条工程链路，但 smoke 超参未超过 SFT baseline。
- 已通过 Ruff、3 个 pytest、17 份 YAML、17 组 Hydra 组合、shell/Python 语法、EN/ZH 引用扫描、checkpoint/sidecar 完整性与 launcher 幂等重跑。

## 2026-07-13 · DSRL（OpenPI + ManiSkill/LIBERO）运行环境

- 已在 `.venv` 安装并验证 `libero`、`mani_skill==3.0.0b22`、`openpi`、`flash-attn==2.7.4.post1`；PyTorch `2.6.0+cu124` 可见 4 张 H20 GPU。
- ManiSkill 资源位于 `/mnt/data/atticux/rlinf/assets/.maniskill`（约 402 MB）；Pi0 LIBERO-Spatial-Object-Goal SFT checkpoint 位于 `/mnt/data/atticux/rlinf/models/RLinf-Pi0-LIBERO-Spatial-Object-Goal-SFT`（约 6.6 GB）。
- 已验证包导入、MuJoCo EGL 导入以及 checkpoint safetensors 头部（777 个张量）。
