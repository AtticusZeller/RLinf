# Development Log

> 已验证完成的任务记录。最新的在最上面。

<!-- 每个任务通过全部必要验证后，在本行下方追加一条 -->

## 2026-07-15 · RECAP / STEAM 默认启用 W&B

- RECAP value、STEAM value 与共享 CFG 基础配置默认同时启用 TensorBoard 和 W&B，统一写入 W&B 项目 ``rlinf``。
- 已验证三份 YAML 解析与 logger backend 值；当前 ``.venv`` 使用 W&B 0.25.0，认证信息已配置。

## 2026-07-14 · RECAP / STEAM · LIBERO-10 Task 0 MVP

- 退役 DSRL（Pi0 + LIBERO-Spatial）的 4 份训练配置、e2e/CI 入口与中英文活跃文档；保留底层通用实现和历史发布记录。
- 新增 YAML 驱动的 RECAP/STEAM full 与 MVP 配置、统一 launcher、三组 LIBERO 评测配置、Wilson 区间汇总器和单元测试；数据与重要产物持久化到 ``/mnt/data/atticux/rlinf/``。
- seed 0 真实跑通 value → advantage → CFG → 100 回合 eval：SFT baseline 32%、RECAP 9%、STEAM 14%。这验证了两条工程链路，但 smoke 超参未超过 SFT baseline。
- 已通过 Ruff、3 个 pytest、17 份 YAML、17 组 Hydra 组合、shell/Python 语法、EN/ZH 引用扫描、checkpoint/sidecar 完整性与 launcher 幂等重跑。

## 2026-07-13 · DSRL（OpenPI + ManiSkill/LIBERO）运行环境

- 已在 `.venv` 安装并验证 `libero`、`mani_skill==3.0.0b22`、`openpi`、`flash-attn==2.7.4.post1`；PyTorch `2.6.0+cu124` 可见 4 张 H20 GPU。
- ManiSkill 资源位于 `/mnt/data/atticux/rlinf/assets/.maniskill`（约 402 MB）；Pi0 LIBERO-Spatial-Object-Goal SFT checkpoint 位于 `/mnt/data/atticux/rlinf/models/RLinf-Pi0-LIBERO-Spatial-Object-Goal-SFT`（约 6.6 GB）。
- 已验证包导入、MuJoCo EGL 导入以及 checkpoint safetensors 头部（777 个张量）。
