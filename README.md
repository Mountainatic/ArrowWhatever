# ArrowWhatever

**ArrowWhatever** 是 macOS 上运行的 Intel Arrow Lake-HX 核显图形驱动项目，关注于 Intel Core Ultra 9 275HX 的 Xe-LPG 核显，在 macOS Tahoe 上构建。

项目基于 [XeGfx](https://github.com/watchthelight-labs/XeGfx) 和 [NvGfx](https://github.com/watchthelight-labs/NvGfx/tree/xe)，结合 [Mesa ANV](https://gitlab.freedesktop.org/mesa/mesa) 与 [XeMTL](https://github.com/watchthelight-labs/NvGfx/tree/497d521e925bd760c8cde5bbc17d9bf96d2ee2b4/plugin)，建立了从 Metal 图形渲染、GPU 命令提交到内建屏显示的完整路径。在此基础上，ArrowWhatever 进一步实现了 Intel 原生显示、高刷新率 HiDPI、零拷贝翻转和 GPU 渲染优化，并使用 [i915](https://github.com/torvalds/linux/tree/master/drivers/gpu/drm/i915) 驱动内建屏，实现了硬件光标和 GPU 加速。

## 当前实现

项目已经打通了 macOS 图形系统与 Intel 核显之间的主要链路。

| 功能     | 实现情况                                                   |
| ------ | ------------------------------------------------------ |
| GPU 加速 | XeGfx、Mesa ANV 与 XeMTL 协同运行，支持 WindowServer 的 Metal 合成 |
| 原生显示   | i915 接管内建 eDP，支持 EDID、DPCD 读取及显示模式设置                   |
| 高刷新率   | 1920×1200 HiDPI @ 240 Hz，3840×2400 后备光栅与双管拼接           |
| 启动显示   | 自动恢复已选择的显示模式，启动后直接进入加速桌面                               |
| 硬件光标   | 独立光标平面，支持高刷新率 HiDPI 下的光标更新                             |
| 显示翻转   | GGTT 零拷贝与逐帧 GPU 完成同步                                   |
| 渲染优化   | Tile4 扫描、IOSurface Device Cache、page-off 与 CCS 压缩      |

当前的开发工作集中在进一步提高 WindowServer 的合成吞吐，优化渲染与显示之间的并行性，并完善不同图形负载下的内存一致性与稳定性。目前实际帧率约 70fps，部分系统 UI 和神奇效果显示有卡顿。

## 工作原理

ArrowWhatever 沿用 XeGfx 的 Intel GPU 驱动基础，通过 XeMTL 将 macOS 的 Metal 图形操作转换为 Vulkan，再由 Mesa ANV 提交给 i915 执行。

显示部分由 XeGfx core、XeGfxDisplay 和 XeGfxAccel 协作完成。驱动从固件获取内建屏信息，经 AUX 读取面板参数，由 i915 建立显示管线并完成模式设置。WindowServer 生成的图像随后通过 GGTT 映射进入显示地址空间，在 GPU 完成渲染后交由显示引擎扫描。

这条链路将图形渲染与显示控制连接起来，也为后续的高刷新率、压缩渲染和显示同步优化提供了基础。

## 主要技术进展

### 原生显示与 240 Hz HiDPI

原生显示接管从读取固件留下的显示状态开始，逐步发展到由 i915 自行设置 eDP 链路、显示模式和扫描平面。

在高分辨率、高刷新率下，驱动使用两条显示管线协同扫描 3840×2400 光栅，并通过 DSC 完成面板输出。显示模式可以保存并在下次启动时恢复，硬件光标也已接入这条显示路径。

相关设计见 [原生显示接管与开机模式](docs/kms-boot-mode.md)。

### 零拷贝与延迟翻转

早期显示路径需要由 CPU 将整帧图像复制到显示缓冲区。ArrowWhatever 使用 GGTT 映射，让显示引擎直接读取 WindowServer 合成的 IOSurface，省去每帧约 16 MB 的 CPU 复制。

在此基础上，K9 延迟翻转将 GPU 完成等待交给内核工作线程，使 WindowServer 可以继续提交工作。最初的 2560×1600、60 Hz 实验中，加速桌面的翻转表现从约 15 fps 提升至约 60 fps。

后续实现进一步引入逐帧完成标记，让工作线程等待当前合成帧对应的 GPU 工作，再于垂直消隐期间完成显示切换。这样能够减少其他 GPU 任务对桌面翻转的干扰。

相关设计见 [K9 延迟翻转](docs/k9-deferred-flip.md)和[帧流水线分析](docs/frame-pipeline.md)。

### Tile4 与压缩渲染

WindowServer 的桌面合成需要频繁读写大尺寸图像。为了改善这类操作的效率，项目引入 Tile4 扫描布局，并为部分 IOSurface 建立适合 GPU 渲染的私有图像。

这些图像可以利用 CCS_E 压缩减少渲染过程中的内存访问。IOSurface Device Cache 与 page-off 机制则负责协调 GPU 私有图像和 CPU 可访问页面之间的数据同步。

在公开的压缩对照实验中，相同测试负载下的翻转吞吐由约 76 次/秒提升至 97–99 次/秒。相关实现也改善了窗口动画中的多层合成表现。

详细机制见 [Tile4、page-off 与渲染压缩](docs/page-off-and-compression.md)。

## 测试与性能

原始日志、驱动构建标识、逐帧时间线及分析工具均已公开：

- [原始测试日志与说明](logs/README.md)
- [数据采集及分析工具](scripts/tools/)
- [帧流水线与性能分析](docs/frame-pipeline.md)

## 构建与使用

项目以补丁形式维护对上游驱动的修改，源码基于两个固定的 NvGfx `xe` 提交：

| 组件               | 上游基点                                                                                                      |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| XeGfx core 与显示组件 | [`5a19a73f`](https://github.com/watchthelight-labs/NvGfx/commit/5a19a73f36249efb99c44c3f9cb34603ef0c0eb8) |
| XeMTL 插件         | [`497d521e`](https://github.com/watchthelight-labs/NvGfx/commit/497d521e925bd760c8cde5bbc17d9bf96d2ee2b4) |

获取对应源码后，按照 [补丁应用说明](patches/README.md) 中的顺序应用补丁，即可建立 ArrowWhatever 的驱动源码树。

项目提供构建、安装、AuxKC 更新、启动验证及回滚工具。外部源码和构建产物通过 `XEGFX_*` 环境变量指定，便于在不同开发环境中组织和复现。

完整流程参见 [构建与安装说明](docs/building.md)。

## 技术文档

| 主题                       | 文档                                               |
| ------------------------ | ------------------------------------------------ |
| 原生显示、双管拼接与硬件光标           | [KMS 显示接管](docs/kms-boot-mode.md)                |
| GGTT 零拷贝                 | [零拷贝翻转](docs/zero-copy-flip.md)                  |
| 延迟翻转                     | [K9 设计记录](docs/k9-deferred-flip.md)              |
| 逐帧 GPU 同步与帧率分析           | [帧流水线](docs/frame-pipeline.md)                   |
| Tile4、Device Cache 与 CCS | [page-off 与压缩](docs/page-off-and-compression.md) |
| userptr 生命周期修复           | [内核崩溃分析](docs/userptr-panic.md)                  |
| 图形内存导入修复                 | [device lost](docs/device-lost.md)               |
| 代码与构建                    | [补丁说明](patches/README.md)                        |
| 测试数据                     | [原始日志](logs/README.md)                           |

## 许可与致谢

ArrowWhatever 基于 [NullMoth Systems](https://nullmothsystems.com) 的 macOS 图形驱动体系，以及 [watchthelight-labs/XeGfx](https://github.com/watchthelight-labs/XeGfx) 和 [NvGfx](https://github.com/watchthelight-labs/NvGfx/tree/xe) 的研究成果。项目同时使用 Mesa ANV、[metal2vulkan](https://github.com/steelbrain/metal2vulkan)、[FreeBSD drm-kmod](https://github.com/freebsd/drm-kmod) 和 Intel i915 等组件。

`patches/` 沿用上游的 **PolyForm Noncommercial License 1.0.0**，用于非商业研究与开发。项目原创的文档和脚本采用 **MIT License**。完整许可条款和第三方来源分别见 [LICENSE](LICENSE)、[LICENSE-MIT](LICENSE-MIT) 与 [NOTICE.md](NOTICE.md)。

感谢上游开发者及相关开源社区的工作。项目由 LLM 驱动构建，自用项目不保证另行情况。
