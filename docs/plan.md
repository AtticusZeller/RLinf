# Development Plan

> 用户和 agent 共同维护的当前计划。最新的在最上面。

<!-- 新条目追加到本行下方，保持最新在最上 -->

## RECAP / STEAM · LIBERO-10 Task 0 MVP

- 退役 DSRL 的 Pi0 + LIBERO-Spatial 实验入口，保留底层通用实现与历史发布记录。
- 默认只运行 seed 0，使用同一 π₀.₅、SFT 数据和 64 条离线 rollout 验证 RECAP 与 STEAM 全链路。
- 价值模型保留 RECAP 1,000 步、STEAM 100 步诊断；STEAM 使用 batch 4 并关闭梯度检查点，优势标注使用每卡 batch 64 / 2 workers，这是根据吞吐与稳定性实测压缩的 smoke 设置。CFG 为 200 步、global batch 256，只验证可训练性与方向性效果。
- 数据原件、标签和 checkpoint 持久化到 OSS，视频训练工作集自动暂存到本地可重建缓存。
- 对 SFT baseline、RECAP、STEAM 各执行 50 个固定初始状态 × 2 轮评测，报告成功率、相对 baseline 变化和 Wilson 95% 区间。
- 保留原 4,096-rollout、三 seed 配置为显式 ``full`` 流程，不作为默认入口。
- seed 0 已验证：baseline 32%，RECAP 9%，STEAM 14%；结论是两条工程链路可用，但当前 smoke 超参数没有超过 SFT baseline。
