# patches/ —— 改动补丁系列

本目录把项目里实际验证过的改动整理成三十四个可以按序应用的补丁。每个补丁开头的注释写明了基点提交、涉及文件、应用命令与改动意图，补丁体本身保持标准 unified diff，`a/` 与 `b/` 前缀可以直接配合 `patch -p1` 或 `git apply`。

## 源码基点与组件补丁链

项目使用四个固定的上游源码基点：

| 源码范围 | 上游基点 | 用途 |
| --- | --- | --- |
| XeGfx core、XeGfxAccel、XeGfxIntelFB、XeGfxAGDC | NvGfx `xe` · `5a19a73f36249efb99c44c3f9cb34603ef0c0eb8` · XeGfx 0.0.44 | GPU、显示、framebuffer、AGDC 与 native-display |
| XeMTL `plugin/` | NvGfx `xe` · `497d521e925bd760c8cde5bbc17d9bf96d2ee2b4` · XeGfx 0.0.35 | Metal → Vulkan/ANV 插件 |
| Mesa（ANV） | Mesa `bffd91947efc1932da99aca69fc540d6d4201b0c`（26.3.0-devel）＋ NvGfx `5a19a73f` 的 `gpu/userland/patches/mesa-macos.patch`、`mesa-xegfx.patch` | Vulkan 驱动 `libvulkan_intel.dylib` |
| libdrm | libdrm `b97cbde15c5c3abfe44d78e8f57139e50f612fec`（2.4.134）＋ NvGfx `5a19a73f` 的 `gpu/userland/patches/libdrm-macos.patch`、`libdrm-xegfx.patch` | Darwin 上的 DRM 替身 `libdrm.2.dylib` |

各组件按下面的补丁链形成当前源码状态：

| 组件 | 补丁链 |
| --- | --- |
| XeGfx core / xkpi | `0001 → 0008 → 0011 → 0020 → 0022 → 0023 → 0028` |
| XeGfxAccel | `0002 → 0009 → 0012 → 0024 → 0029` |
| XeGfxIntelFB | `0003 → 0010 → 0014` |
| XeGfxAGDC | `0004 → 0013 → 0017 → 0030` |
| XeGfxDisplay | `0015 → 0018 → 0021 → 0025` |
| native-display tools | `0016 → 0019 → 0027 → 0034` |
| XeMTL | `0005 → 0006 → 0007 → 0026 → 0031` |
| libdrm | `0032` |
| Mesa ANV | `0033` |

### 逐补丁前置状态

下面的“前置状态”描述该补丁应用前所在的组件状态；源码基点由上表统一给出。

| 序号 | 补丁 | 前置状态 | 涉及文件 |
| --- | --- | --- | --- |
| 0001 | `0001-xg_vm-userptr-race.patch` | XeGfx 0.0.44 · `5a19a73f` | `gpu/xegfx/shim/src/fbsd/xg_vm.c` |
| 0002 | `0002-accel-vblank-and-head4.patch` | XeGfx 0.0.44 · `5a19a73f` | `kexts/NVRM/accel/nvrm-accel.cpp`，新增 `kexts/NVRM/accel/xegfx_accel_names.h` |
| 0003 | `0003-intelfb-panel-timing.patch` | XeGfx 0.0.44 · `5a19a73f` | `kexts/XeGfxIntelFB/intelfb.cpp`，新增 `xe/firmware-timing.h`、`xe/panel-timing.h`、`nvrm-agdc-k5.h` |
| 0004 | `0004-agdc-k5-panel-timing.patch` | XeGfx 0.0.44 · `5a19a73f` | `kexts/NVRMAGDC/nvrm-agdc.cpp`、`kexts/NVRMAGDC/xe/Info.plist`，新增 `xe/firmware-timing.h`、`xe/panel-timing.h` |
| 0005 | `0005-plugin-xemtl-port.patch` | XeGfx 0.0.35 · `497d521e` · `plugin/` | 插件目录整体改编 |
| 0006 | `0006-plugin-host-import.patch` | 本系列 0005 之后的插件树 | `plugin/nvmtl_vk.c` |
| 0007 | `0007-plugin-first-loss-journal.patch` | 本系列 0006 之后的插件树 | 新增 `plugin/nvmtl_first_loss.h`；修改 `plugin/nvmtl_vk.c`、`plugin/nvmtl_vk.h`、`plugin/XeMTLDevice.m` |
| 0008 | `0008-core-ggtt-flip-slots.patch` | `0001` | 修改 `gpu/xegfx/shim/include/xg_i915.h`、`gpu/xegfx/shim/src/xnu/xg_kext.cpp`、`gpu/xkpi/src/i915/xg_i915_exec.c`；新增 `gpu/xkpi/src/i915/xg_i915_flip.c` |
| 0009 | `0009-accel-zero-copy-flip.patch` | 本系列 0002 之后的加速器文件 | `kexts/NVRM/accel/nvrm-accel.cpp`、`kexts/NVRM/accel/xegfx_accel_names.h` |
| 0010 | `0010-intelfb-detailed-timings.patch` | 本系列 0003 之后的 framebuffer 文件 | `kexts/XeGfxIntelFB/intelfb.cpp` |
| 0011 | `0011-core-native-display-m0-m4a.patch` | `0001 → 0008` | `gpu/xegfx/shim/src/xnu/xg_kext.cpp`、`gpu/xegfx/shim/include/xg_i915.h`、`gpu/xkpi/src/i915/xg_i915_flip.c`、`gpu/xkpi/exclude.txt`；新增 `gpu/xkpi/src/i915/{xg_display_hook.c,xg_display_hook.h,intel_bios.c,intel_display_driver.c}`；构建脚本路径可配置 |
| 0012 | `0012-accel-m3d-m4a-present-bootarm.patch` | `0002 → 0009` | `kexts/NVRM/accel/{nvrm-accel.cpp,nvaccel_stubs.h,xegfx_accel_names.h,xe/Info.plist}` |
| 0013 | `0013-agdc-m3d-in-kernel-arm.patch` | `0004` | `kexts/NVRMAGDC/nvrm-agdc.cpp`、`xe/Info.plist`；删除 `xe/firmware-timing.h`、`xe/panel-timing.h` |
| 0014 | `0014-intelfb-l0-ready.patch` | `0003 → 0010` | `kexts/XeGfxIntelFB/intelfb.cpp` |
| 0015 | `0015-adapter-xegfxdisplay-kms.patch` | 创建 XeGfxDisplay 组件 | 新增 `kexts/XeGfxDisplay/{Info.plist,src/XeGfxDisplay.h,src/XeGfxDisplay.cpp,src/xegfx_kms_kapi.h}` |
| 0016 | `0016-tools-native-display-bringup.patch` | 创建 native-display tools | 新增 `tools/` 下的 M0–M4a 启动、安装与守护脚本 |
| 0017 | `0017-agdc-pending-retry.patch` | `0004 → 0013` | `kexts/NVRMAGDC/nvrm-agdc.cpp` |
| 0018 | `0018-adapter-intel-class-name.patch` | `0015` | `kexts/XeGfxDisplay/src/XeGfxDisplay.{h,cpp}`、`Info.plist` |
| 0019 | `0019-guard-tools-class-name-and-keep-armed.patch` | `0016` | `tools/m3db-health.py`、`xegfx-ws-preflight.py`、`m4a2-verify.sh`、`m3db-preflight.sh`、`m3db-control.py` |
| 0020 | `0020-core-aux-edid-dpcd.patch` | `0001 → 0008 → 0011` | `gpu/xkpi/src/i915/xg_display_hook.{c,h}`、`gpu/xegfx/shim/src/xnu/xg_kext.cpp` |
| 0021 | `0021-adapter-edid-ddc.patch` | `0015 → 0018` | `kexts/XeGfxDisplay/src/XeGfxDisplay.{h,cpp}` |
| 0022 | `0022-core-k1-staged-edp-takeover.patch` | `0001 → 0008 → 0011 → 0020` | `gpu/xegfx/shim/src/xnu/xg_kext.cpp`、`gpu/xkpi/src/i915/{xg_display_hook.c,xg_display_hook.h,intel_bios.c,intel_display_driver.c}`、`gpu/xkpi/exclude.txt`；新增 `gpu/xkpi/src/i915/intel_modeset_setup.c` |
| 0023 | `0023-core-kms-boot-commit-joiner-cursor.patch` | `0001 → 0008 → 0011 → 0020 → 0022` | `gpu/xegfx/shim/src/xnu/xg_kext.cpp`、`gpu/xegfx/shim/include/xg_i915.h`、`gpu/xkpi/src/i915/{xg_display_hook.c,xg_display_hook.h,intel_display_driver.c,intel_modeset_setup.c,xg_i915_exec.c}`、`gpu/xkpi/exclude.txt`；新增 `gpu/xkpi/src/i915/i915_gem_execbuffer.c` |
| 0024 | `0024-accel-deferred-flip-tile4-pageoff.patch` | `0002 → 0009 → 0012` | `kexts/NVRM/accel/{nvrm-accel.cpp,xegfx_accel_names.h}` |
| 0025 | `0025-adapter-kms-modes-cursor-bootmode.patch` | `0015 → 0018 → 0021` | `kexts/XeGfxDisplay/src/{XeGfxDisplay.h,XeGfxDisplay.cpp,xegfx_kms_kapi.h}` |
| 0026 | `0026-plugin-marks-tile4-pageoff.patch` | 本系列 0007 之后的插件树 | `plugin/{NVMTLEventSync.m,NVMTLObjects.h,NVMTLObjects.m,XeMTLDevice.m,nvmtl_vk.c,nvmtl_vk.h}` |
| 0027 | `0027-tools-frame-rate-and-pageoff-measurement.patch` | `0016 → 0019` | `tools/m4a2-bootguard.sh`、`tools/m3db-preflight.sh`；新增 `tools/` 下的帧率、page-off 测量工具，`tools/e1/`、`tools/apple-kc/` |
| 0028 | `0028-core-ccs-scanout-surface-import-mmap.patch` | `0001 → 0008 → 0011 → 0020 → 0022 → 0023` | `gpu/xegfx/shim/include/{xg_fd.h,xg_i915.h,xg_vm_xnu.h,xg_xnu.h}`、`gpu/xegfx/shim/src/fbsd/{xg_fd.c,xg_kern.c,xg_lock.c,xg_mem.c,xg_misc.c,xg_vm.c}`、`gpu/xegfx/shim/src/xnu/{xg_fd.cpp,xg_kext.cpp,xg_vm.cpp}`、`gpu/xkpi/src/i915/{xg_display_hook.c,xg_i915_flip.c,xg_i915_map.c}`；新增 `gpu/xkpi/include/linux/io.h` |
| 0029 | `0029-accel-ccs-scanout-surface-ticket.patch` | `0002 → 0009 → 0012 → 0024` | `kexts/NVRM/accel/{nvrm-accel.cpp,xegfx_accel_names.h}` |
| 0030 | `0030-agdc-colour-stages-bgra-plane.patch` | `0004 → 0013 → 0017` | `kexts/NVRMAGDC/{nvrm-agdc.cpp,nvrm-agdc-k5.h}` |
| 0031 | `0031-plugin-ccs-scanout-surface-import-arena.patch` | 本系列 0026 之后的插件树 | `plugin/{NVMTLEventSync.m,NVMTLObjects.h,NVMTLObjects.m,XeMTLDevice.m,nvmtl_vk.c,nvmtl_vk.h}` |
| 0032 | `0032-libdrm-stale-export-and-trace.patch` | libdrm `b97cbde1` ＋ NvGfx 的两个 libdrm 补丁 | `xf86drm_xegfx.c` |
| 0033 | `0033-mesa-anv-xemtl-residency-pointer-push.patch` | Mesa `bffd9194` ＋ NvGfx 的两个 Mesa 补丁 | `src/intel/compiler/brw/brw_shader.cpp`、`src/intel/vulkan/` 下 13 个文件（含 `i915/anv_batch_chain.c`） |
| 0034 | `0034-tools-genie-fps-timeline-anv-harness.patch` | `0016 → 0019 → 0027` | 新增 `tools/{genie-fps.m,genie-fps.sh,tl-summ.py,dt-tgt.py,rearm-after-fallback.sh}`、`tools/livelog/`、`tools/anv/` |

## 应用方法

在 XeGfx 0.0.44 基点 `5a19a73f` 上应用 core 与显示组件补丁：

```sh
cd NvGfx-5a19a73

for n in 0001 0002 0003 0004 0008 0009 0010 0011 0012; do
  patch -p1 < /path/to/patches/$n-*.patch
done

patch -p1 -E < /path/to/patches/0013-agdc-m3d-in-kernel-arm.patch

for n in 0014 0015 0016 0017 0018 0019 0020 0021 0022 0023 0024 0025 0027 0028 0029 0030 0034; do
  patch -p1 < /path/to/patches/$n-*.patch
done
```

`0013` 会移除两个时序头文件，`-E` 用于同步删除应用后为空的文件。

在 XeGfx 0.0.35 基点 `497d521e` 的 `plugin/` 上应用 XeMTL 补丁：

```sh
cd NvGfx-497d521
patch -p1 --remove-empty-files < /path/to/patches/0005-plugin-xemtl-port.patch
patch -p1 < /path/to/patches/0006-plugin-host-import.patch
patch -p1 < /path/to/patches/0007-plugin-first-loss-journal.patch
patch -p1 < /path/to/patches/0026-plugin-marks-tile4-pageoff.patch
patch -p1 < /path/to/patches/0031-plugin-ccs-scanout-surface-import-arena.patch
```

`--remove-empty-files` 用于处理 `0005` 中的文件替换。最终得到当前 core/display 源码树与 XeMTL plugin 源码树。

Mesa 与 libdrm 先按 NvGfx 的 `gpu/userland/scripts/build_mesa.sh`、`build_libdrm.sh` 打上 NvGfx 自带的移植补丁，再应用本系列：

```sh
cd mesa                      # bffd91947efc
patch -p1 < NvGfx-5a19a73/gpu/userland/patches/mesa-macos.patch
patch -p1 < NvGfx-5a19a73/gpu/userland/patches/mesa-xegfx.patch
patch -p1 < /path/to/patches/0033-mesa-anv-xemtl-residency-pointer-push.patch

cd libdrm                    # b97cbde15c5c
patch -p1 < NvGfx-5a19a73/gpu/userland/patches/libdrm-macos.patch
patch -p1 < NvGfx-5a19a73/gpu/userland/patches/libdrm-xegfx.patch
patch -p1 < /path/to/patches/0032-libdrm-stale-export-and-trace.patch
```

`0033` 按 Mesa 的 AGENTS.md 标注为 `Generated-by: LLM`，不向 Mesa 源码添加注释；这不是向 Mesa 上游提交的改动。

## 验证方式

补丁系列使用对应上游基点进行重放验证：

1. 在 `5a19a73f` 上按组件链应用 core、accel、IntelFB、AGDC、XeGfxDisplay 与 tools 补丁
2. 在 `497d521e` 的 `plugin/` 上应用 `0005 → 0006 → 0007 → 0026 → 0031`；Mesa、libdrm 在各自基点加 NvGfx 移植补丁之后应用 `0033`、`0032`
3. 对补丁后的源码文件与实际构建输入做逐文件比对
4. 检查 unified diff 应用结果、符号标记与新增文件

当前 0.0.44 组件链、XeMTL plugin 链以及 Mesa、libdrm 补丁均可完整重放，没有 `.rej`；0028–0034 涉及的 96 个文件与实际构建输入逐字节一致。native-display tools 使用脚本自身位置解析仓库内文件，外部源码树与构建产物通过 `XEGFX_*` 环境变量传入。

补丁来源由上面的四个固定上游基点和当前项目源码状态共同确定。
