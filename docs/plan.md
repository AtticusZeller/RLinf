# Development Plan

> 用户和 agent 共同维护的当前计划。最新的在最上面。

<!-- 新条目追加到本行下方，保持最新在最上 -->

## STEAM Medium · seed 1 两卡复现

- 使用与历史 Medium 相同的 30 条 SFT 和固定清单中的 256 条 rollout，仅改变训练
  seed 为 1。
- baseline、STEAM step 500 和 step 1,000 统一固定 eval seed 0；不同训练 seed 的
  评测日志写入独立 `eval-seed-0/` 路径。
- 两卡执行 500-step ensemble value、advantage、1,000-step CFG 和两档各 100 回合
  评测；本轮不重复 RECAP。
- 两卡 2-step value smoke 已完成并保存 checkpoint；正式 run 已归档：baseline 40%、
  STEAM step 500 为 51%、step 1,000 为 66%，每项 100 回合。结果仍需更多训练
  seed 和 benchmark 才能判断稳定性。

## RECAP / STEAM · LIBERO-10 Task 0 Medium

- 新建 ``docs/experiment-log.md``，集中记录实验假设、配置、W&B、产物、结果与结论；``docs/log.md`` 继续只记录已验证的开发任务。
- 使用 30 条 SFT 与按成功/失败比例、seed 0 确定性抽取的 256 条 rollout；保存原 episode 映射清单。
- RECAP 使用 2,000-step value，STEAM 使用 500-step ensemble value；两者 CFG 均为 1,000 steps。
- 对 baseline 与两种方法的 CFG step 500/1,000 各评测 100 回合。若两种方法都未超过 baseline 且 500→1,000 没有上升，则停止，不进入 full。
- 数据、checkpoint 与结果写入 ``/mnt/data/atticux/rlinf/``，训练与评测同步 W&B 项目 ``rlinf``。
- 已完成：STEAM Medium 的四卡 advantage SIGSEGV 后改用 GPU 0–2 三卡完成
  advantage；服务器迁移后从 ``global_step_500`` 在两张 H20 恢复至 step 1,000，
  并完成两档评测与汇总。RECAP step 1,000 为 60%，STEAM 最佳为 step 500 的
  55%，均高于 35% SFT baseline；不自动进入 full。

## RECAP / STEAM · LIBERO-10 Task 0 MVP

- 退役 DSRL 的 Pi0 + LIBERO-Spatial 实验入口，保留底层通用实现与历史发布记录。
- 默认只运行 seed 0，使用同一 π₀.₅、SFT 数据和 64 条离线 rollout 验证 RECAP 与 STEAM 全链路。
- 价值模型保留 RECAP 1,000 步、STEAM 100 步诊断；STEAM 使用 batch 4 并关闭梯度检查点，优势标注使用每卡 batch 64 / 2 workers，这是根据吞吐与稳定性实测压缩的 smoke 设置。CFG 为 200 步、global batch 256，只验证可训练性与方向性效果。
- 数据原件、标签和 checkpoint 持久化到 OSS，视频训练工作集自动暂存到本地可重建缓存。
- 对 SFT baseline、RECAP、STEAM 各执行 50 个固定初始状态 × 2 轮评测，报告成功率、相对 baseline 变化和 Wilson 95% 区间。
- 保留原 4,096-rollout、三 seed 配置为显式 ``full`` 流程，不作为默认入口。
- 后续 RECAP/STEAM 训练与评测默认同时记录 TensorBoard 和 W&B，统一写入 W&B 项目 ``rlinf``。
- seed 0 已验证：baseline 32%，RECAP 9%，STEAM 14%；结论是两条工程链路可用，但当前 smoke 超参数没有超过 SFT baseline。
