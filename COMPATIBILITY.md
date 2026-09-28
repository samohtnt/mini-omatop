# Compatibility verification

Checked for version 1.1.0 on 2026-09-27. Passing synthetic inputs verifies parsing and layout; it
does not certify hardware or drivers that were not available for testing.

## Results

| Area | Coverage | Result |
| --- | --- | --- |
| Live machine | AMD Ryzen 7 PRO 3700U, 8 logical CPUs, Radeon Vega, encrypted NVMe/Btrfs root, 1920×1080 | Passed sampling, display, toggle, persistence, and process-lifecycle checks |
| CPU fixtures | 1–512 logical CPUs, noncontiguous IDs, hotplug, counter resets, large counters, guest/steal accounting | Passed |
| Display geometry | 60 width/count combinations: 320–7680 logical pixels and 1–512 logical CPUs | Passed; slots remain bounded and nonoverlapping |
| Software rendering | Pixel checks at 1×, 1.25×, 1.5×, 2×, and 3× | Passed |
| OpenGL rendering | Pixel checks on this machine at 1×, 1.25×, 1.5×, and 2× | Passed |
| Vulkan rendering | Pixel checks on this machine at 1× and 1.5× | Passed |
| Live virtual monitor | Hotplug alongside the physical monitor; 1280×720, 2560×1440, 3840×2160 at 2×, 2560×1440 at 1.25×, portrait 1080×1920, and 3440×1440 | Passed CPU/menubar spacing and network-edge positioning; one sampler across both displays |
| Storage fixtures | SATA/ext4, NVMe/XFS, eMMC/ext4, virtio/ext4, device-mapper/Btrfs, and mdraid/XFS | Passed device identification and read/write counter parsing |
| Non-block root fixtures | NFS, overlay, tmpfs, and ZFS | Capacity remains available; no activity flash without a matching block device |
| Capacity/RAM fixtures | Empty/full/zero-capacity filesystems, reserved blocks, very large counters; 256 MiB–1 TiB RAM | Passed |
| Network fixtures | IPv4, IPv6, dual stack, Wi-Fi-style names, VPN interfaces, interface changes, counter resets, missing routes, and rejected/inactive routes | Passed |
| Missing inputs | Missing/malformed proc records and unavailable filesystem statistics | No crash or non-finite output |

The Python suite has 40 tests, including the isolated-launch security
regression. The full QML suite reports 78 passes, including
data-driven cases and suite setup/cleanup. Extra rendering runs cover the scale
and backend combinations above.

The live tests used Python 3.14.7, Qt 6.11.2, and Quickshell 0.3.1 on Omarchy
development build `4.0.0.r6663.g3faafba`. Most live checks used an installed
copy with a local 3-pixel thickness override. The repository's default 1-pixel
single row on smaller monitors was checked by QML tests and the clean install
tests below.

## Release lifecycle and stability

The 1.1.0 candidate was installed through Omarchy's real plugin commands using
a local Git origin containing all source, tests, and documentation.

- Installed the previous 1.0.9 commit, then updated to 1.1.0. Every candidate
  file matched the source checkout after the update.
- Verified the default single CPU row is 1 logical pixel on this 1080p display,
  switching logical mode on makes it 6 pixels, and the setting survives a shell
  restart. The menubar follows the CPU row without overlap.
- Removed the test installation while enabled: zero sampler processes, zero
  meter windows, and the menubar returned to the top edge. Repeated with a
  fresh 1.1.0 install, which starts with logical mode off.
- Confirmed manual side/bottom reservations survive removal; they belong to
  the monitor configuration. The README explains their cleanup.
- Observed the live sampler for 300.73 seconds at 5-second intervals (61
  samples): one unchanged process, RSS steady at 17,128 KiB, three file
  descriptors, and 0.27 CPU seconds consumed (about 0.09% of one CPU core).
  These measurements cover the sampler, not the shared shell's rendering cost.
- Terminated only the sampler child: the shell started one replacement in
  1.52 seconds and preserved the logical CPU setting.

The final regression run passed all 40 Python tests and 78 QML cases.
This is a bounded smoke/soak check, not evidence of hours-long stability.
Actual suspend/resume, physical cable reconnects, and other GPU/CPU families
remain untested. Virtual output hotplug coverage is listed above.

## Boundaries

- The plugin requires Linux procfs and a compatible Omarchy shell/Quickshell API.
  Other operating systems, older shell APIs, and arbitrary Wayland compositors
  are not verified. No Intel, NVIDIA, or ARM hardware was physically tested.
- There is no GPU telemetry or vendor-specific GPU code. Qt handles rendering;
  passing OpenGL/Vulkan here does not certify other driver versions or GPUs.
- Three pixels means three **logical** pixels. Physical thickness increases
  with display scaling. When there are more logical CPUs than available pixels,
  some slots have zero width; every CPU cannot remain individually readable.
- Logical CPU meters measure non-idle time, not frequency, temperature, or
  throughput. Heterogeneous performance/efficiency cores have equal-width slots.
  CPU steal time counts as non-idle; guest time is not counted twice. Container
  procfs may expose host totals rather than a container's quota.
- Storage usage is for `/` only. The flash follows the root mount's identified
  block device, not every disk. Multi-device Btrfs activity may be incomplete;
  ZFS pools, network roots, and overlay backing devices are not traversed.
- Network meters show rates relative to a shared decaying peak, not link
  saturation. Policy routing and split-tunnel VPNs may not be represented by
  the default routes in procfs. With no usable default route, summing all
  non-loopback interfaces can count traffic on both a bridge/tunnel and its
  underlying interface.
- Missing aggregate counters/capacity read as zero; a missing logical CPU
  baseline is unfilled. The current UI has no separate unavailable indicator.
- The top reservation is automatic. The three other edges still need the
  documented per-monitor reservations. Remove the old manual top reservation
  when upgrading. Live compositor tests used the top menubar; alternate bar
  positions, HDR, mirroring, VRR, and multi-GPU output routing were not tested.

## Repeatable checks

```sh
python3 -m unittest discover -s tests -v

QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import tests/qml/imports
```

For the rendered pixel check, add `QT_SCALE_FACTOR=1.25` (or another tested
factor) and append `DisplayCompatibility::test_rendered_rows_and_gaps` to the
test command. The capture accounts for device pixel ratio, including software
grabs that lose their DPR metadata.

For hardware-backed checks in a Wayland session, unset `QT_QUICK_BACKEND`, use
`QT_QPA_PLATFORM=wayland`, and set `QSG_RHI_BACKEND=opengl` or `vulkan`. This tests
the available local renderer; it does not emulate another GPU vendor.

The fixtures follow the [Linux procfs documentation](https://docs.kernel.org/filesystems/proc.html)
and [block I/O counter documentation](https://docs.kernel.org/admin-guide/iostats.html).
Rendering uses [Qt Quick's scene graph](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph-renderer.html).
