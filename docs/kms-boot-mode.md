# i915 接管内建屏：K2–K4、joiner、Tile4 平面、硬件光标

配合 `patches/0023`（core）、`patches/0025`（XeGfxDisplay）、`patches/0024`（accel 的 joiner 跟随与 Tile4）阅读。

## 为什么要接管

K1（`0022`）之前，面板一直沿用固件点亮的 2560×1600@60 光栅，驱动只翻 `PLANE_SURF`。缩放的 HiDPI 和 240/300 Hz
都要 i915 自己编程面板：HBR3 加 DSC、平面缩放器，以及 3840×2400 高刷新率时单条 pipe 带不动所需的 pipe joiner。
接管按 NVRAM `xegfx-disp-kms` 分阶段进行，没有这个键时行为和 0022 一样。

| 阶段 | NVRAM | 做什么 |
| --- | --- | --- |
| K1 | 1 | 只读：建立 encoder/connector，读出固件点亮的 pipe（`0022`） |
| K2a | 2 | 只做 `drm_atomic_check_only`：先检查读出的状态，再检查适配器的 scanout 几何，不写任何寄存器 |
| K2 | 3 | 开机时经 i915 提交一次（DRRS 关、8 bpc、PSR 关），主平面上放占位 framebuffer，然后记录固定模式 |
| K3 | — | KAPI v1 扩展：`getTiming(XG_KMS_FIXED_MODE_BASE + n)` 取固定模式 n，`setMode(ctx, 0, n)` 提交；换桌面尺寸只做 plane-only 提交 |
| K4 | — | 开机直接进上次的模式：`xegfx-disp-bootmode` 由适配器写入（`'XBM1'`、刷新率 mHz、桌面宽、高） |

## J1 joiner

3840×2400 在 240/300 Hz 下超出单条 pipe 的像素率，pipe A 和 pipe B 就合并（joined）扫描。core 用 `"xgJoinerInfo"`
告诉 accel，pipe B 的平面相对 pipe A 指向哪里；accel 每次翻页把两半一起写，K4 开机后的第一次 present 也会重读一遍。

## Tile4 平面

`xg_display_kms_plane_layout()` 用 Tile4 modifier 把占位 framebuffer 重新提交一次（plane-only，不 modeset，joiner
状态不变），i915 就会改写 `PLANE_CTL` 的 tiling、按 tile 计的 stride 和 pipe B 的偏移。DPT 在开机时关闭
（`enable_dpt=0`）。accel 按每一帧的布局切换平面（见 `page-off-and-compression.md`）。

## C1 硬件光标

没有硬件光标时，WindowServer 把指针画进每一帧 3840×2400 的合成，指针只能和整帧一样快。i915 在 joiner 下移动光标
需要完整的 atomic commit（`intel_legacy_cursor_update` 没有 joiner 快速路径），所以 core 只提交一次，把 i915 的
光标平面放在两条 pipe 的接缝上，让 i915 为两边都分配 DDB 和水位，之后每条 pipe 的 `CUR_POS`/`CUR_CTL`/`CUR_BASE`
由 KAPI reserved[6] `cursorImage`、reserved[7] `cursorMove` 直接写。光标平面不经过缩放器，图像预先按光栅缩放。
适配器把 `kIOHardwareCursorAttribute` 报告为 1，移动合并到 vblank 线程。

## K4 开机模式

以前每次开机先 60 Hz，WindowServer 起来以后再切到 HiDPI@240，切换要一次 modeset，光标在这之前大约 30 s 动不了。
K4 之后：

1. 适配器每次 `setDisplayMode` 成功，都把模式写进 `xegfx-disp-bootmode`；
2. core 的 K2 开机提交直接跑这个固定模式和桌面（需要时 joined），被拒绝就退回 60 Hz 的提交；
3. `getTiming(XG_KMS_BOOT_STATE_INDEX)` 报告开机实际提交的状态，适配器据此把对应的 detailed timing 报告为当前模式，
   WindowServer 起来时面板已经在这个模式上，不需要再 modeset。

关闭：往 `xegfx-disp-bootmode` 写 16 个零字节。

## 现状

ARL-HX（Xe-LPG，7D67）日常使用：开机直接 1920×1200 HiDPI@240（3840×2400 后备，joined），光标立即可用。
