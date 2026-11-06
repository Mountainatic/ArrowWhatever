# 压缩扫描、按 surface 导入、GEM 映射上限与帧率

配合 `patches/0028`–`0037` 阅读。前一轮（`page-off-and-compression.md`）让 WindowServer 的私有拷贝带上渲染压缩（CCS），
但扫描输出仍然要先把内容拷回线性页面；这一轮让显示直接扫描压缩图像，并处理了这条路上暴露出来的几个问题。
测量都在 ARL-HX（Core Ultra 9 275HX，iGPU 7D67）、macOS 26（25G241）、内建屏 1920×1200 HiDPI@240（3840×2400）上做，
原始日志在 `logs/2026-11-04`、`logs/2026-11-05`。

## 压缩扫描（core 0028、accel 0029、插件 0031）

- 插件把 scanout surface 画进一张 Tile4 + MTL RC CCS 图像（不做 fast clear：MTL_RC_CCS 没有给显示用的清除色），导出它的内存，
  在 WindowServer 的 DRM 文件里找回 GEM handle，用 core 的 `BO_SCANOUT` 钉住页面、拿到 token，再用 accel 的 selector 9 登记
  （surface ID、token、主平面 pitch、CCS 偏移与 pitch）。core 核对对象大小，handle 不对就放弃。
- accel 翻到这张 surface 时，flip slot 直接指向压缩图像自己的页面（`xgScanoutPhys`），平面切到第三种布局
  `I915_FORMAT_MOD_4_TILED_MTL_RC_CCS`（`xgPlaneLayout2`），不再需要 page-off 把内容拷回线性页面。显示可能还在扫描的
  token 不会被释放；登记跟着 DRM client 走，WindowServer 退出或重启时一起清掉。
- accel 的 IOSurface device cache 改用加速器自己的 accelerator ID：CoreDisplay 把 surface 放上平面时用这个 ID 做
  `bind_accel`，原来自造的 ID 对不上，每次换平面都触发一次 page-off（GPU 拷回，约 17 ms）。
- 开关：`debug.xegfxaccel_iop_xe_ccs`（默认 1），boot-arg `xegfxccs=0`；计数 `iop_xe_ccs_frames` / `_regs` / `_fail`。

## 按 surface 导入 IOSurface（core 0028、accel 0029、插件 0031）

WindowServer 画的每个窗口 surface 都要导入成 GEM 对象。原来走 userptr：第一次 execbuffer 时逐页 pin 用户映射，约 2 µs 一页，
大头是 shim 为每一页建的 vm_page 记录。现在插件在 host-pointer 导入之前先向 accel 要一张票（selector 11，accel 在调用者的
task 里找到 surface，把它的 IOMemoryDescriptor 交给 core），再用 `SURF_EXPECT` 在 ANV 的 DRM 文件上声明“接下来这个指针和大小
的导入就是它”；随后那一次 `GEM_USERPTR` 得到的是由 surface 自己的物理内存段组成的对象（一次 `prepare()` 布线，没有
struct page）。没对上的声明 2 秒后作废。统计在 `debug.xegfx_uhold`。

## GEM 映射上限（core 0028）

插件需要第二个描述符池（约 150 MB）时，ANV 映射失败（`mmap failed`，每次让 WindowServer 停顿约 1 s）。用 `tools/anv/map-test.c`、
`cum-test.c` 测：同一进程里 30 个 32 MB 映射都没问题，单个映射却在 48–64 MB 以上失败，开机久了上限一路往下掉
（刚开机时 152 MB 能成功）。原因：`xg_map_ranges()` 用 `kcalloc(页数, 8)` 分配两个数组，而 LinuxKPI 的 kmalloc 超过一页就是
`contigmalloc`，在这里是 `IOMallocContiguous`，XNU 的空闲内存碎了以后拿不到连续块；64 MB 映射要两块 128 KB 的物理连续内存。
改成 `kvcalloc` 之后，第二个池正常打开，`debug.xegfx_mem` 里新加的 `contig fails` 是 0。

## ANV：地址表后面的常量 push（Mesa 0033）

插件把每个 Metal buffer 参数变成一个 64 位指针，放在 binding 640 的动态 UBO 地址表里，着色器的常量于是都是
“从表里取指针再读”，每次一个 SEND。ANV 现在把这种读取当成 push 范围：画的时候从表里读出指针（含动态偏移），
从 `地址 & ~31` 开始 push，地址的低 5 位作为驱动常量传给着色器。对 WindowServer 的 280 个片段着色器，有 25 个受影响，
SEND 1224 → 167，估计周期 −32.9%。只读 SSBO 也用同样的办法 push。开关：`/Library/GPUBundles/.xemtl-no-ssbo-push`
或环境变量 `XEMTL_SSBO_PUSH=0/1`；`XEMTL_PTR_PUSH_*` 调阈值。

第一版装上以后，应用的 Metal 图层（和 macOS 26 的玻璃背景）合成出来是黑的。原因是指针范围用的是地址表本身的
set/index，ANV 原有的 UBO 降级在给普通的表读取（表的第 48–55 字节，也就是一个指针）找 push 范围时匹配到了它，读到的是
push 上来的数据而不是指针，后面经过这个指针的读取全是垃圾。修复是在那里和 push-descriptor 分析里跳过指针 / SSBO 范围。
验证工具在 `tools/anv/`：从 WindowServer 自己的 SPIR-V 缓存取出全部片段着色器，用插件同样的方式降级，在确定的输入下
push 开、关各画一次逐字节比较；修复后 278 个完全一样，另外 2 个只在着色器没写的通道上不同。

（按 Mesa 的 AGENTS.md，关于 Mesa 改动、由 AI 撰写的文字要带标记词：biblioklept。补丁本身标注 `Generated-by: LLM`，
不向 Mesa 源码加注释；这不是向 Mesa 上游的提交。）

## AGDC：颜色级、BGRA 平面与平面大小（AGDC 0030）

CoreDisplay 通过 AGDC K5（0x711）问显示管线的能力。原来的回答让它认为平面没有 gamma、也不能取 BGRA，于是每一帧在扫描之前
多跑一个全屏的 GPUPass。现在按 Apple ICL framebuffer 对内建屏的回答：颜色级（CSC 矩阵、两张 1024 项的表）、平面格式 BGRA、
平面缩放上限等于当前桌面大小（3840×2400，而不是面板的 2560×1600 时序）。

## 帧率：为什么大多数帧占两个 vblank

翻页流水线只有一帧深：WindowServer 合成 → accel 等这一帧的合成标记 → 写 PLANE_SURF → 等锁存 → 通知 WindowServer → 下一帧。
240 Hz 下一帧要赶上下一个 vblank，合成必须在 4.17 ms 以内。稳定测试（`scripts/tools/genie-fps`）里合成 p50 是 4.4 ms，
所以大多数帧落到再下一个 vblank，两帧间隔 p50 8.1 ms，约 120 fps。

主要原因是 GPU 频率停在最低档：测试期间 `debug.xegfx_gt_act` 只有 0（RC6）和 550 MHz（最高 1900）。flip worker 等的是插件的
合成标记，不是 i915 的 fence，没有任何等待会触发 i915 的 waitboost；一帧深的流水线里合成又总是立刻开始执行，i915 只给还没
开始的请求提频。SLPC 看到 GPU 大约一半时间在忙，就停在效率频率，而这颗 GPU 的效率频率就是最低档（RP1 = RPn = 550 MHz）〔推断〕。
通过 SLPC 写一次最低频率（`sysctl -w debug.xegfx_gt_min=…`，再写回 550）以后，SLPC 恢复调频（忙时平均约 770 MHz），
同样的负载变成 151–174 fps，合成 p50 1.4 ms，两帧间隔 p50 4.4 ms（`logs/2026-11-05/tl-steady-*.txt`）。之后它还会再卡住，
“刚开机快、过一阵变慢”就是这个。0036 的迟到帧频率下限修掉了它（见下文）。`genie-fps.sh` 每次运行都记下忙时频率和停在
550 MHz 的比例，卡住的时候能从 `data/fps-history.tsv` 看出来。

## 神奇效果

- GPU 侧最贵的是 Core Animation 的背景捕获：每帧约 1.5 次把整屏（菜单栏以下 3840×2341）从 scanout 拷进一张私有图像，
  一次约 1 ms，接近内存带宽，换着色器快不了。打开“降低透明度”以后捕获减半，神奇效果却没有变快，所以它不是瓶颈。
- 只跑神奇效果时的时间线：合成 p50 4.7 ms，锁存 2.3 ms，WindowServer 收到通知后排进下一帧 p50 7.6 ms、p90 31 ms。
  WindowServer 主线程在动画期间约一半时间在 CPU 上（Core Animation 自己的渲染为主），另一半在等消息；Dock 的动画线程按
  计时和通知推进，自己几乎不占 CPU。这是一个串行的循环，单独砍掉某一段拷贝不会让它翻倍。
- 驱动这边能直接减的：动画期间的 userptr 导入和 GEM mmap，以及插件里两处 `@synchronized` 的锁竞争，合计约占主线程 8%。
- E2（锁存之前就通知）在 WindowServer 轮换 3 个 scanout surface 时重测过：仍然有 hazard（WindowServer 画进正在扫描的
  surface），稳定帧率反而减半，保持关闭。

## 卡死诊断（core 0028、accel 0029）

偶尔会有一个 CPU 连调试器的 NMI 都不响应的卡死。最常见的原因是一次永远不完成的寄存器读取，所以 core 的 `linux/io.h`
覆盖层把 `readl` / `readq` 记在每个 CPU 的看门狗槽里，accel 的显示寄存器读取也经 `xgMmioHooks` 记进去；槽里还有线程、
三层调用者、正在等的 spin mutex 和它的持有者。看门狗 panic 时把每个 CPU 的这些信息和超过 1 ms 的寄存器读取（以 i915 MMIO
窗口里的偏移表示）一起打印出来。`tools/livelog/` 把内核和 CoreDisplay 的显示日志实时写到磁盘，强制重启以后还能看到卡死前的
最后几秒。

## 硬件色彩：夜览和颜色描述文件（core 0035、accel 0036）

AGDC 回答了显示管线的颜色级（0030）以后，CoreDisplay 不再在 GPUPass 里做颜色，而是把线性化表、颜色矩阵、编码表随每个显示事务
交给显示管线；以前没人读这些，所以拖夜览滑块没有效果。现在 accel 在 `performTransaction` 里读事务的 pre / post gamma 表和
3×4 颜色矩阵（Apple 的 ICL 驱动在这里调用 framebuffer 的 `PerformGammaTransaction` / `PerformCscTransaction`），翻页之前交给
core，core 用一次只涉及 CRTC 的原子提交写进 i915 的 `DEGAMMA_LUT`、`CTM`、`GAMMA_LUT`（约 5 ms）。和上次提交一样的状态跳过
（CoreDisplay 大约每秒把同样的表当成新对象再送一次）。默认打开、不限速，boot-arg `xegfxcolour=0` 关。早先的版本每秒最多提交一次，
跳过了拖动中间的状态，看起来像滞回（往一边拖到某一点突然变黄，往回拖到某一点突然变白）。HDR 还没有做（需要 PQ、10 位扫描和 HDR
元数据）。

## 老帧：按命令缓冲编号的 surface 标记（accel 0036、插件 0037）

用户看到“动画结束后又从中间放一遍”。翻页在扫描一个 surface 之前等插件的合成标记，等不到 100 ms 就照样扫描；WindowServer 轮换三个
scanout surface，没画完的那个里还是两三帧之前的内容。测量（`ws late` 日志、i915 请求计时）表明 GPU 并不慢：迟到的合成都是
“调度 +0 ms、一个 part、没有事件等待”，同一时间 i915 没有超过 50 ms 的请求。原因在标记本身：插件给每个 surface 只有一个内核标记，
所有写它的命令缓冲都结束才释放，而 WindowServer 在 scanout surface 上的命令缓冲会首尾重叠，于是标记可以一直挂 200 ms 以上，
翻页也在等它的事务之后才提交的工作。

现在（DRM client selector 13）每个命令缓冲有自己编号的标记，写完一个 surface 就释放自己的编号；事务排队时记下当时最新的编号，
翻页只等编号不超过它的标记，也就是交换之前提交的工作（Apple 的语义）。等待上限 100 → 200 ms，放弃等待的标记后来清掉时记一行日志。
旧的 selector 1/2 保持不变，没有 selector 13 的 accel 上插件退回旧协议。

## GPU 频率：迟到帧抬高下限（core 0035、accel 0036）

翻页取到一帧 3 ms 后合成还没完成（这一帧要错过 vblank），accel 通过 core 的 `xgGtMin` 把 SLPC 最低频率抬到最高，最后一个迟到帧
之后 150 ms 放回。Linux 的显示路径对错过 vblank 的翻页 fence 做同样的事；i915 自己的 waitboost 在这里不会触发（翻页等的是插件的标记，
不是 i915 fence，而且合成早已开始）。sysctl：`debug.xegfxaccel_iop_xe_boost_us`（3000，0 关）、`_boost_hold_ms`、`_boost_mhz`、
`_mark_ms`；计数 `iop_xe_late`、`_boosts`、`_boost_floor`、`_late_cleared`。

## 11-06 测量与一处更正

- 更正：0033 的修复版 ANV 直到 11-06 才真正装上。11-04 21:47 到 11-06 之间装着的是没有修复的那一版，而且 `.xemtl-no-ssbo-push`
  一直在，两种 push 都是关着的；11-05 记下的“Metal 区域恢复正常、神奇效果约 79 fps”是在 push 关着的情况下测的。0033 的说明已经改正。
- 0035–0037 加上修复版 ANV（push 打开）之后，开机 4 分钟测（`genie-fps.sh 6 3`）：稳定 **126 fps**（p99 20.9 ms，最长 29 ms；
  同一天只有频率下限时是 52–68 fps、p99 191 ms），神奇效果 **92.8 fps**（之前 42），测量期间没有一次标记超时；合成 pop→mark p50
  2.55 ms（之前 6.5），WindowServer 的 i915 请求平均 2.9 ms（之前 7.9）。Metal 区域正常、没有再看到老帧（用户确认）。
- 离 240 Hz 还差的：一帧从 vblank 开始是 WindowServer 的 CPU（约 1.3 ms）加合成（约 2.5 ms），刚好在 4.17 ms 边上，所以部分帧赶上
  一个 vblank，中位数还是两个。合成里最贵的是 Core Animation 的整屏背景捕获（3840×2341，每帧约 1.65 次）。
- 11-06 有一次登录后约 140 s 的整机卡死（一个 CPU 连 NMI 都不响应），和 11-04 的一次一模一样，以前的版本也出现过，原因还没定位；
  开机守护按设计退回 IntelFB，重新 arm 之后正常。

