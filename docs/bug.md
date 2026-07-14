# Bug Journal

> 开发过程中的硬核经验：触发情况、解决方案、原因解释。

<!-- 新 bug 追加到本行下方 -->

## 2026-07-14 · STEAM 高并发多卡优势标注被 SIGTERM 终止

- **触发：** 每卡 ``batch_size=256``、12 个视频 worker 时，SFT 标注完成后在 rollout 首批被外部 ``SIGTERM`` 终止；CUDA 没有 OOM，Python 也没有异常。
- **修复：** MVP 改为每卡 ``batch_size=64``、2 个 worker；SFT/rollout 分别以约 5.8/6.1 秒每 batch 完成，显存约 16–25 GB/卡。
- **原因：** 4 个 rank 同时预取并解码双相机视频会造成较大的瞬时宿主内存和共享资源压力；当前环境没有保留可确认信号来源的内核记录，因此不能把 ``SIGTERM`` 等同于 CUDA OOM。降低并发后同一数据与 checkpoint 可稳定完成。

## 2026-07-14 · 多卡离线视频标注耗尽文件描述符

- **触发：** 4 个 rank 各启用 12 个 DataLoader worker，批量传递双相机张量时出现 ``Too many open files (24)``；直接从 OSS 随机 seek 视频也会显著降低吞吐。
- **修复：** launcher 将文件描述符软限制提高到 65,536，并把 1.4 GB MVP 数据集暂存到 ``$HOME/.cache``；标签完成后只把 metadata 同步回 OSS。
- **原因：** PyTorch multiprocessing 为共享张量创建大量文件描述符，而 TorchCodec 的逐帧视频 seek 对对象存储的随机读取延迟敏感。
