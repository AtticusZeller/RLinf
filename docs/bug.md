# Bug Journal

> 开发过程中的硬核经验：触发情况、解决方案、原因解释。

<!-- 新 bug 追加到本行下方 -->

## 2026-07-15 · STEAM Medium 四卡 advantage 初始化触发 SIGSEGV

- **触发：** STEAM Medium value 完成后，使用 ``torchrun --nproc-per-node=4``
  生成 ensemble advantage；进程尚未读取数据或写入 sidecar 时，local rank 3
  以 exit code ``-11`` 退出。``torch.distributed.elastic`` 随后向 rank 0–2
  发送 ``SIGTERM``，使整个 advantage 阶段失败。
- **恢复：** 保留已完成的 STEAM value checkpoint，并以
  ``CUDA_VISIBLE_DEVICES=0,1,2 RLINF_NPROC=3`` 仅重跑 advantage，避开发生
  故障的物理 GPU 3；成功后继续原有 1,000-step CFG 与 step 500/1,000 的评测，
  不重跑 baseline、RECAP 或 STEAM value。
- **原因与边界：** 日志只显示 TensorFlow/oneDNN 原生初始化后发生段错误，
  没有 Python traceback、CUDA OOM 或数据读取日志；目前只能归类为多进程
  原生运行时不稳定，不能归因于 STEAM 算法或数据。单卡探针已越过初始化，
  支持先排除通用单进程故障；三卡恢复在吞吐与隔离 rank 3 之间折中。

## 2026-07-15 · RECAP value validation 缺少同 tag returns sidecar

- **触发：** value YAML 的 ``eval_data_paths`` 指向离线 eval 数据集，但
  returns YAML 只覆盖训练数据；FSDP worker 在构造 validation dataset 时因
  找不到同 tag sidecar 全部退出，GPU 随即空闲。
- **修复：** returns 阶段必须覆盖 value 阶段的所有 ``eval_data_paths``；
  增加配置测试，断言 validation 路径是 returns 路径的子集且 tag 相同。
- **原因：** Hydra 只能验证各 YAML 能否组合，无法发现跨阶段数据产物依赖；
  baseline 成功也不能证明后续 value 数据链完整，必须检查 sidecar 契约。

## 2026-07-14 · STEAM 高并发多卡优势标注被 SIGTERM 终止

- **触发：** 每卡 ``batch_size=256``、12 个视频 worker 时，SFT 标注完成后在 rollout 首批被外部 ``SIGTERM`` 终止；CUDA 没有 OOM，Python 也没有异常。
- **修复：** MVP 改为每卡 ``batch_size=64``、2 个 worker；SFT/rollout 分别以约 5.8/6.1 秒每 batch 完成，显存约 16–25 GB/卡。
- **原因：** 4 个 rank 同时预取并解码双相机视频会造成较大的瞬时宿主内存和共享资源压力；当前环境没有保留可确认信号来源的内核记录，因此不能把 ``SIGTERM`` 等同于 CUDA OOM。降低并发后同一数据与 checkpoint 可稳定完成。

## 2026-07-14 · 多卡离线视频标注耗尽文件描述符

- **触发：** 4 个 rank 各启用 12 个 DataLoader worker，批量传递双相机张量时出现 ``Too many open files (24)``；直接从 OSS 随机 seek 视频也会显著降低吞吐。
- **修复：** launcher 将文件描述符软限制提高到 65,536，并把 1.4 GB MVP 数据集暂存到 ``$HOME/.cache``；标签完成后只把 metadata 同步回 OSS。
- **原因：** PyTorch multiprocessing 为共享张量创建大量文件描述符，而 TorchCodec 的逐帧视频 seek 对对象存储的随机读取延迟敏感。
