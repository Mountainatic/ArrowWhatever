# 帧流水线：按合成排序的延迟 flip，以及帧率卡在哪里

配合 `patches/0024`（accel）、`patches/0026`（插件）、`patches/0027`（测量工具）阅读，接在 `k9-deferred-flip.md` 后面。

## 从 K9 到按帧排序

K9（`0009`、`0012`）的 worker 在写 `PLANE_SURF` 之前等**整个 GT 空闲**。这样做顺序是对的，但任何别的进程的
长 batch 都会拖住翻页：一个应用一次提交几百 ms 的 GPU 工作，WindowServer 的翻页就要跟着等。现在的顺序是：

1. **surface 标记**：插件在 commit 时把 WindowServer 这一帧的 surface 标成 pending，GPU 做完以后标成 ready
   （DRM client selector 1）。accel 的 worker 只等这一帧自己的标记（`markonly`），快照或 GT 空闲轮询只作为后备。
2. **WindowServer 不再等**：插件的 `commitAndWaitUntilSubmitted` 只等 scheduled（`/private/tmp/xemtl-ws-nowait`，
   开机由 `tools/e1` 的 LaunchDaemon 重建），排序完全交给 accel。
3. **HIGH 优先级**：WindowServer 的 Vulkan 队列用 `VK_KHR_global_priority` 的 HIGH，GuC 先调度它的合成。
4. **超时也照样 arm**：GPU 忙超过 `iop_xe_idle_ms`（默认 120）时照样上屏这一帧，并计入 `idle_forced`，不会再
   因为连续失败把 defer 永久关掉；卡住的事务由逃生口直接报告完成，同样不会关掉 defer。

## 每帧时间线

`debug.nvaccel_iop_xe_tl` 输出最近 200 帧相邻步骤之间的微秒数：排进队列 → worker 取出 → 合成完成（mark）→
写 `PLANE_SURF`（arm）→ 帧计数器变化（latch）→ 通知 WindowServer → 下一帧排进来。fps-probe 1800×1100、
HiDPI@240、Tile4 开时（`logs/2026-10-31/tl-probe-*.txt`）：

| 步骤 | page-off 关（p50 / p90） | 默认配置（p50 / p90） |
| --- | --- | --- |
| 两帧之间的间隔 | 12.5 / 27 ms | 8.6 / 19 ms |
| 取出 → 合成完成 | 8.5 / 12 ms | 5.4 / 6.2 ms |
| arm → latch | 2.4 / 4.0 ms | 1.8 / 4.0 ms |
| 通知 → 下一帧排进来 | 30 µs / 14 ms | 1.3 / 12.8 ms |
| 翻页/s | 58 | 82 |

## 帧率卡在哪里

- WindowServer 在两个 surface 之间轮换（双缓冲）。它下一帧要画的 surface 正是上一帧还在扫描的那个，所以收到通知
  后几十 µs 内就排进下一帧，也就是说它一直在等这个通知。流水线深度是 1：合成 → 等 vblank → 通知 → 下一帧合成。
- 写完 `PLANE_SURF` 就通知（E2，`iop_xe_early`）能省掉等 vblank 的那段，但双缓冲下下一帧会画进还在扫描的 surface
  （撕裂、残留光标）。所以 E2 只在 WindowServer 连续轮换三个以上 surface 时才会生效，默认关闭。
- 因此在 240 Hz 下，一帧占 ⌈(合成 + arm) / 4.17 ms⌉ 个 vblank：合成 8.5 ms 时占 3 个（80 fps），2–4 ms 时占 2 个
  （120 fps）。想稳定 120 Hz，日常合成要压到 4 ms 以内，这就是 `page-off-and-compression.md` 的出发点。
- Dock 神奇效果这种负载每帧要往窗口大小的临时 surface 上叠 5–14 层，每层都是整张读写，受内存带宽限制
  （双通道 DDR5-5600，峰值 89.6 GB/s，实测 41–60 GB/s），单帧合成 15–60 ms。

## 计数器

`iop_xe_flips`、`markonly_flips`、`defer_max_depth`、`idle_forced`、`mark_timeouts`、`iop_xe_tl`；core 的
`debug.xegfx_gt`（GPU 频率）和 `debug.xegfx_eb`（execbuffer 分段计时）。
