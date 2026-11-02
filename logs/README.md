# logs/ —— 原始测量日志

ARL-HX（Core Ultra 9 275HX，iGPU 7D67，Xe-LPG）、macOS 26（25G241）、内建屏 1920×1200 HiDPI@240（3840×2400 后备，
pipe joined）上采集的原始日志，用来对照延迟 flip 与 page-off 的行为。每一份都注明了采集时的驱动构建（kext 二进制
SHA-256 的前 12 位）。10-30 的构建是 `0024`/`0026` 之前的中间版本，最终状态见补丁 `0023`–`0027`。

这里没有持续大量磁盘 I/O 下的测试，也从没遇到过多小时后整机卡死。早期 2560×1600@60（K9 刚做好的 60 fps 阶段）
没有保留逐帧的翻页日志，那时的数字见 `docs/k9-deferred-flip.md`。

## 2026-10-30：按合成排序之前和之后（HiDPI@240）

| 文件 | 内容 | 构建 |
| --- | --- | --- |
| `anim-genie-1810.tsv` | `tools/anim-probe`：自己的窗口最小化再恢复（神奇效果），每 20 ms 记录翻页数、是否按序、是否 forced、worker 等 GPU 的时间、arm 时间 | accel `e708488e2959`（等 GT 空闲，运行时 `early=0`、`idle_ms=120`） |
| `anim-genie-small-1828.tsv`、`anim-genie-large-1828.tsv` | 同上，小窗口 500×330 和大窗口 1800×1100，加 GPU 频率列 | 同上，core 带 GPU 频率读数（`debug.xegfx_gt_act`） |
| `anim-genie-mark-small.tsv`、`anim-genie-mark-large.tsv` | 同上，worker 改为只等这一帧合成的标记之后 | accel UUID 90ED0224 + 插件 `5d28d1339731` |
| `mark-timeouts.txt` | `tools/mark-timeout-watch.sh`：标记等待超时（100 ms）累计次数、最长等待、快照超时、forced 的时间序列。21:53–21:55 另一个进程在跑一次几百 ms 的 GPU 基准 | 同上 |

列：`t_s` 秒，`phase` idle/动画，`flips` 这 20 ms 里的翻页数，`ordered`/`forced` 按序或超时强制 arm 的翻页，
`idle_last_us` worker 最后一次等 GPU 的时间，`arm_last_us` 写 `PLANE_SURF` 到锁存，`gt_mhz` GPU 实际频率。

## 2026-10-31：Tile4、page-off、压缩、每帧时间线

| 文件 | 内容 | 构建 |
| --- | --- | --- |
| `tile4-on-passtime.log.gz` | 插件 passtime：Tile4 扫描刚开的时候，每个 pass 的 GPU 时间 | accel `749168b50da3`、插件 `9001f0f2949f` |
| `pageoff-probe-passtime.log.gz` | fps-probe 期间的 passtime，page-off 延迟升级版（131 翻页/s） | accel `9f9e03d718ea`、插件 `bfc4b0b29d67` |
| `pageoff-tile4-probe-passtime.log.gz` | 同上，加 Tile4 | 同上，`iop_xe_tile4=1` |
| `ccs-on-passtime.log.gz`、`ccs-off-passtime.log.gz` | 压缩 A/B：fps-probe 各两次，私有拷贝带 CCS 和 `INTEL_DEBUG=noccs`（97–99 对 76 翻页/s） | accel `9f9e03d718ea`、插件 `0a26febb51ee` |
| `genie-lazy-flips.txt`、`genie-lazy-passtime.log.gz` | 两次神奇效果，60 s：`tools/flip-sampler.pl`（每 10 ms 一次翻页计数，ms 与累计数）和 passtime（带每个 pass 的 draw 次数）；临时 surface 还是 linear | accel `9f9e03d718ea`、插件 `c23c5688366b` |
| `genie-coherent-flips.txt`、`genie-coherent-passtime.log.gz`、`genie-coherent-plugin.log` | 同上，私有拷贝立即建立，并带一致性规则（最忙的几秒 89/85/76 对 60/59/48 翻页/s） | accel `7f8443ddc21e`、插件 `31b5f29a17c4` |
| `tl-probe-pageoff-off.txt` | `debug.nvaccel_iop_xe_tl`：fps-probe 期间最后 200 帧的时间线，page-off 关，Tile4 开（58 翻页/s） | accel `b9ca64f267e3`、插件 `31b5f29a17c4`（page-off 开关文件被重启清掉） |
| `tl-probe-defaults.txt` | 同上，默认配置（82 翻页/s） | accel `8ee59d21f885`（= `0024`）、插件 `9d368ef407c4`（= `0026`） |
| `xe-locks.txt`、`ws-drawn.txt` | `debug.nvaccel_iop_xe_locks`：WindowServer 画过的 surface 收到的 GPU 标记和 CPU 锁 | accel `b087cad01a63`（lock watch） |

passtime 每行：`cb` 命令缓冲序号、`pass` 序号、目标尺寸、格式、`gpu_us`、与上一个 pass 的间隔 `gap_us`、
前四个不同的着色器哈希，新版本末尾还有 `draws`。时间线每行：两帧间隔、排队到取出、取出到合成完成、合成完成到 arm、
arm 到锁存、锁存到通知、通知到下一帧排进来（µs），最后是 surface ID、是否提前通知、是否成功。

汇总脚本：`tools/passtime-summ.py`、`tools/passtime-sizes.py`、`tools/anim-summary.py`。分析见 `docs/frame-pipeline.md` 和
`docs/page-off-and-compression.md`。
