# page-off、渲染压缩（CCS）与 Tile4 扫描

配合 `patches/0024`（accel）、`patches/0026`（插件）阅读。思路来自 Apple 的 Intel 驱动：IOSurface 的内容在 GPU 那边
另有一份 device cache（Tile 布局并压缩），CPU 或别的使用方要读的时候，再拷回线性页面。

## 为什么

WindowServer 原本直接画进线性的 IOSurface 页面。在 ANV 上，往线性 render target 画要花 Tile4 的 8–13 倍 GPU 时间，
合成越慢，帧率越低（见 `frame-pipeline.md`）。Apple 的 ICL 驱动默认开着渲染压缩，IOSurface 也压缩
（`AllowIOSurfaceRenderCompression` 默认 1），并且由内核管理 device cache。

## Tile4 扫描（accel + 插件）

插件通过 DRM client selector 2 告诉 accel 每个 WindowServer surface 的布局；scanout surface 在 Tile4 打开时直接画成
Tile4，打开或关闭时由 GPU 原地重排；平面按每一帧的布局切换。默认打开，boot-arg `xegfxtile4=0` 从关闭开始，
`debug.xegfxaccel_iop_xe_tile4` 可以在运行时切换；10 s 内切换布局超过 20 次会自动关闭。全屏 pass 画进 scanout
从 4.6 ms 降到 1.5–3.4 ms。

## page-off（accel selector 5–8 + 插件）

- WindowServer 的 render target（BGRA8、≥1024×600、不是 scanout）画进插件的私有 optimal-tiling 图像，而不是线性页面。
  ARL 的核显（Xe-LPG，和 MTL 同一代，`has_aux_map`）上，ANV 会给这种图像加 CCS_E 压缩：图像内存比像素多出正好 1/256。
- 每次合成之后，accel 挂在这个 surface 上的 `IOSurfaceDeviceCache` 被标成 current。CPU 加锁时，IOSurface 会调用它的
  控制函数（op 0）：accel 先等这个 surface 已提交的合成完成，再请插件的 page-off 线程把私有图像拷回页面（最多 300 ms）。
  翻页或拷贝这个 surface 之前也一样（最多 50 ms）。
- surface 正被锁着时不标 current（读 IOSurface 的 +0x228 只读锁数、+0x22c 写锁数，macOS 25G241）：WindowServer 截屏时
  先锁住 surface、再让 GPU 往里画、在锁内读，加锁那一刻还没有 current 的 cache，之后的写入就到不了它在读的页面。
- 一秒内被 page-off 超过 4 次、或者变成 scanout 的 surface，退回直接画在页面上。

## 一致性（截屏为什么曾经是白的）

私有拷贝只在插件里，同一个 surface 上别的纹理看不见它。前后三次截屏出错的原因：

1. 截屏 surface 被锁着时还标了 current（上面那条修复）；
2. "从没写过就清零"的捷径：WindowServer 写截屏 surface 时不会增加 seed，清零把已有内容抹掉了（现在只是实验开关）；
3. 旧私有拷贝在释放时写回页面，这时它已经从弱表里消失了，新纹理同时直接画页面，旧内容晚到一步就把新内容盖掉了。

现在的规则：一个 surface 只有在私有拷贝是它在本进程里唯一的 root 时才保留私有拷贝；后来的 root 如果不能做成它的 view，
就先把私有拷贝退回页面；私有拷贝从释放开始到写回完成都拿着 surface 的同步对象，新 root 交出去之前先在上面等一下。
活不到 2 s 或者从没被画过的私有拷贝，之后不再为这个 surface 建。

## 效果

| 测量 | 之前 | 之后 |
| --- | --- | --- |
| 压缩 A/B（fps-probe，翻页/s） | 76（`INTEL_DEBUG=noccs`） | 97–99 |
| 压缩 A/B，超过 12 ms 的 cb | 38 | 2 |
| 神奇效果最忙的几秒，翻页/s | 60、59、48 | 89、85、76 |
| 窗口大小 surface 每次 draw | 2.6 ms | 1.4 ms |

## 开关（插件默认值）

| 文件 | 作用 |
| --- | --- |
| `/Library/GPUBundles/.xemtl-no-pageoff`、`/private/tmp/xemtl-no-pageoff` | 关闭 page-off（跨重启 / 到下次开机） |
| `/Library/GPUBundles/.xemtl-pageoff-lazy`、`/private/tmp/xemtl-pageoff-lazy` | 改为活 3 s、画 100 次后才升级成私有拷贝 |
| `/private/tmp/xemtl-noccs` | 实验：WindowServer 下次启动时用 `INTEL_DEBUG=noccs` 关闭压缩 |
| `/private/tmp/xemtl-pageoff-fastclear` | 实验：从没写过的 surface 清零而不上传（会让截屏变白） |

统计：`sysctl -n debug.nvaccel_iop_xe_po`（page-off 次数、耗时、超时、因为被锁而拒绝的次数）。
