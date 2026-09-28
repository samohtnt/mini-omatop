# mini-omatop

A minimal Omarchy plugin with one meter on each screen edge: CPU at the top, RAM on the left, root filesystem on the right, and network at the bottom. An optional second CPU row shows each logical CPU without adding labels or a separate panel.

```text
             <--- CPU --->
             +-----------+
      RAM ^  |  screen   |  ^ DISK
             +-----------+
          <-- Upload | Download -->
```

Each monitor gets 1-pixel meters below 1200 logical pixels of height, or 3-pixel meters at 1200 and above. CPU grows outward from the horizontal center; RAM and root filesystem grow upward from the bottom edge. All dimensions are **logical pixels**; physical thickness increases with display scaling.

[Install](#install-on-omarchy) · [Logical CPUs](#optional-logical-cpu-row) ·
[Update](#update) · [Troubleshooting](#troubleshooting) ·
[Develop](#develop) · [Changelog](CHANGELOG.md)

## Requirements

- Linux with readable procfs and Python 3 at `/usr/bin/python3`. The sampler uses only the standard library; no pip packages are needed.
- An Omarchy shell with plugin support, Quickshell, and Qt Quick. The logical CPU switch uses the shell's `updateEntryInline` API.
- For the monitor configuration examples below, Hyprland with Omarchy's Lua configuration.

Verified with Python 3.14.7, Qt 6.11.2, Quickshell 0.3.1, and Omarchy development build `4.0.0.r6663.g3faafba`. These are tested versions, not established minimum requirements. See [compatibility verification](COMPATIBILITY.md) for hardware coverage and limitations.

## Optional logical CPU row

Show two CPU rows at the top of each screen: logical CPUs above, total CPU below. Each row is 3 logical pixels tall, for a total of 6 pixels on every monitor. This is off by default.

```sh
omarchy-shell shell call troy.mini-omatop logicalCpu on
omarchy-shell shell call troy.mini-omatop logicalCpu off
omarchy-shell shell call troy.mini-omatop logicalCpu toggle
omarchy-shell shell call troy.mini-omatop logicalCpu status
```

Run these commands after enabling the plugin. A successful command returns `on` or `off`; `status` reads the current setting without changing it.

The setting is saved as `showLogicalCpu` in this plugin's `plugins[]` entry in `~/.config/omarchy/shell.json` and survives shell restarts. Editing that boolean also updates the display live. The `toggle` command can be assigned to a keyboard shortcut. For a manual edit, merge this field into the existing entry, preserving its other settings and the rest of the file:

```json
{ "id": "troy.mini-omatop", "showLogicalCpu": true }
```

The logical row automatically divides the screen width between the CPUs reported by `/proc/stat`, ordered by numeric CPU ID. There is no configured core count: SMT threads are separate logical CPUs, and CPUs appearing or disappearing are detected on the next sample. A new CPU stays unfilled until two samples establish its usage. The row uses a softer accent, small gaps, center-out fills, and no peak markers. Gaps shrink on narrow screens with many CPUs. At extreme counts, individual CPUs cannot be distinguished when there are fewer screen pixels than CPUs.

The total row keeps its existing center-out fill and peak markers. All CPU readings share one `/proc/stat` read per second and one sampler process across monitors. Turning the option off removes the logical row's visual objects and restores the original single-row height.

The CPU strip reserves its own top space, adjusting immediately when this option is toggled. Upgrading from 1.0.x requires removing the old manual top reservation; see [Update](#update). The CPU strip remains below ordinary windows, stays click-through, and hides with the menubar.

## Appearance

The bottom network meter is one split bar. Upload grows leftward from the center, and download grows rightward. The two halves share a decaying peak, so their lengths show the relative rates. The idle track and panel background are transparent; traffic fills and fading peak marks appear when data moves.

The other three edge strips use the bar's background color. Meter fills use the active Omarchy theme: accent for CPU and download, bar text for RAM and upload, and muted for filesystem. As usage rises, each fill blends toward the theme's bar active color. Clicks pass through.

Colors are bound to Omarchy's live theme palette, so a theme switch updates the fills, tracks, peak marks, and bar-matched backgrounds without restarting the shell.

Changes smaller than one logical pixel are accumulated before starting another fill animation. Empty and full readings always apply. Set `MINI_OMATOP_REDUCED_MOTION=1` in the shell environment and restart the shell to use immediate fills without peak fades or disk flashes.

The fills rise smoothly over 280 ms and fall over 900 ms. A thin theme-colored high-water mark stays at the latest peak for 1.4 seconds, then fades over 4.2 seconds. The total CPU row shows the mark at both ends of its center-out fill; each network half shows one mark at its outer end, and RAM shows it at the upper end.

The top nine pixels of the filesystem usage fill flash when the root filesystem's block device completes reads or writes. If `/` is on a network or virtual filesystem without a local block device, usage still works but the I/O flash is unavailable.

## Install on Omarchy

Install from GitHub:

```sh
omarchy plugin add https://github.com/samohtnt/mini-omatop.git --enable
```

Or install from a local Git repository:

```sh
omarchy plugin add /path/to/mini-omatop --enable
```

The installer clones into `~/.config/omarchy/plugins/troy.mini-omatop`, validates the manifest, and enables the panel. Local installs clone committed files only; commit changes before testing installation from a development checkout. `keepLoaded` mounts the panel for the session, so the meters appear as soon as the shell loads the plugin. The logical CPU row starts off; enable it with the command above.

The CPU strip reserves the top automatically. Back up `~/.config/hypr/monitors.lua`, then add `reserved_area` to each monitor's existing `hl.monitor` rule to keep windows clear of the other three strips. Preserve its mode, position, scale, and any reservations required by other panels. Use 3 pixels on the other edges for monitors at least 1200 logical pixels tall:

```lua
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto",
  reserved_area = { top = 0, bottom = 3, left = 3, right = 3 } })
```

Use `{ top = 0, bottom = 1, left = 1, right = 1 }` for monitors below 1200 logical pixels tall. The empty output matches monitors without a more specific rule. If your configuration has output-specific rules, set `reserved_area` on each rule to match that monitor's meter thickness. Scale settings can change a monitor's logical height.

Hyprland places a top bar below the CPU strip and keeps tiled windows clear of the side and bottom strips. After editing the monitor rules, reload and check for configuration errors:

```sh
hyprctl reload
hyprctl configerrors
```

### Update

For an installation managed through Git:

```sh
omarchy plugin update troy.mini-omatop
```

**Upgrading from 1.0.x:** remove only the manual top space previously added for mini-omatop from each monitor's `reserved_area`. Use `top = 0` if nothing else requires a manual top reservation. Keeping the old reservation adds an extra gap above the menubar. Leave the side and bottom reservations in place, then reload Hyprland and check for errors as shown above.

If you customized files in the installed checkout, back them up and review `git diff` there before updating. An update may refuse to fast-forward when local changes conflict; preserve those changes before resolving the conflict. Logical CPU mode remains off unless you enable it, and its saved setting survives subsequent updates and shell restarts.

### Install without Git

From the root of an extracted release archive, with no existing installation at the target path:

```sh
mkdir -p ~/.config/omarchy/plugins
cp -r . ~/.config/omarchy/plugins/troy.mini-omatop
omarchy-shell shell rescanPlugins
omarchy plugin enable troy.mini-omatop
```

This copy has no Git remote and cannot use `omarchy plugin update`; back up and replace it with a newer release when needed. Do not put a symlink in the plugin folder. Omarchy rejects plugins that contain symlinks.

## Hide / show

The meters stay up while the plugin is enabled. To tuck them away without removing it:

```sh
omarchy-shell shell hide troy.mini-omatop
omarchy-shell shell summon troy.mini-omatop '{}'
```

If the menubar autohides, the meters hide with it.
Hiding the plugin explicitly or hiding the menubar stops its sampler until the meters are shown again.

## Remove

```sh
omarchy plugin remove troy.mini-omatop
```

Removing the plugin releases its automatic top reservation. Also remove the
left, right, and bottom reservations you added for mini-omatop from each monitor
rule in `~/.config/hypr/monitors.lua`, keeping any space needed by other panels.
Those manual reservations are owned by your monitor configuration and cannot
be safely removed by the plugin itself.

## What it reads

| Meter | Source |
| --- | --- |
| CPU | `/proc/stat` idle/total deltas |
| RAM | `/proc/meminfo` (`MemTotal` − `MemAvailable`) |
| Download / upload | `/proc/net/dev` receive and transmit bytes on IPv4/IPv6 default-route interfaces, or all non-loopback interfaces when there is no default route; shared decaying peak (1 MB/s floor) |
| Root filesystem | `os.statvfs("/")`, used space as a percentage of used plus user-available space |
| Root disk activity | `/proc/self/mountinfo` identifies the root block device; `/proc/diskstats` reports completed reads and writes |

CPU, RAM, traffic counters, and disk activity update every second. Default routes are cached for at most five seconds and refreshed immediately when interfaces appear or disappear; filesystem capacity is refreshed every 30 seconds. A route change between existing interfaces can take up to five seconds to appear.

The plugin runs one long-lived Python 3 child process for sampling. Its QML runs inside `omarchy-shell`; plugins are unsandboxed, so read the files before enabling them.

The sampler uses Python isolated mode and does not make network connections.
See the [security review](SECURITY_REVIEW.md) for the checks and trust boundaries.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No meters | Enable the plugin and ensure the menubar is visible. An explicitly hidden plugin needs the `summon` command above. Validate and rescan using the commands below. |
| Extra gap above the menubar | Remove the old mini-omatop manual top reservation; the plugin now reserves that space itself. |
| `settings unavailable` from a logical CPU command | Check that the plugin is enabled and its entry exists in valid `~/.config/omarchy/shell.json`. Rescan after correcting the configuration. Older shell APIs are not verified. |
| `could not save settings` | The shell rejected the settings update. Check the configuration file's ownership/write permissions and shell diagnostics before retrying. |
| A logical CPU slot is empty | It may be idle, have no valid baseline yet, or be narrower than a pixel at very high CPU counts. Wait for another sample. |
| Network meter seems too full or too small | It is scaled against a decaying traffic peak, not the interface's advertised speed. VPN and bridge limitations are documented in the compatibility report. |
| Disk usage works but no I/O flash | The flash requires a matching root block device. Network roots, overlay filesystems, and some storage layouts cannot provide it. Reduced motion also disables the flash. |
| QML edits do not appear | Rescan plugins; restart the shell if it retains a cached component. |

Validate and reload an installed plugin:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/troy.mini-omatop
omarchy-shell shell rescanPlugins
omarchy restart shell
```

To check sampling independently of the display:

```sh
/usr/bin/python3 -I -u ~/.config/omarchy/plugins/troy.mini-omatop/sample.py --once
```

Expect one JSON object containing `cpu`, `cpuLogical`, `ram`, `down`, `up`, `disk`, and `diskPulse`. Missing aggregate counters read as zero; a logical CPU without a valid baseline has `usage: null`. The interface does not distinguish unavailable data from an idle meter.

## Develop

See [compatibility verification](COMPATIBILITY.md) for the tested CPU, rendering,
display, storage, and network configurations and their limits.

```sh
python3 -m unittest discover -s tests -v
```

On an Omarchy machine, after copying into `~/.config/omarchy/plugins/troy.mini-omatop`, saving a QML file reloads the plugin. You can also force it:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/troy.mini-omatop
omarchy-shell shell rescanPlugins
```

If the shell keeps an older cached QML component, run `omarchy restart shell`.

The code is organized by responsibility:

- `sample.py` reads counters and emits typed snapshots, including logical CPUs ordered by ID.
- `Sampler.qml` owns the single child process and applies snapshots.
- `Panel.qml` handles settings, visibility, and the four screen-edge windows.
- `CpuStrip.qml` arranges the optional logical row and total row. Usage updates reuse meters; CPU topology changes rebuild their slots.
- `MeterStrip.qml` draws fills, peak markers, and disk activity with shared animation behavior.

Layout, rendered-pixel, and animation regression tests use Qt 6 Quick Test with a test-only palette. The command below requires the Qt test runner, which is a development dependency rather than a plugin runtime requirement:

```sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import tests/qml/imports
```

For a useful bug report, include the plugin version, Omarchy/Quickshell/Qt/Python versions, display resolution and scale, logical CPU count, reproduction steps, and any relevant validation or test output. Review diagnostics for personal information before sharing. See [compatibility verification](COMPATIBILITY.md) for the distinction between automated fixtures and hardware tested directly.

## License

[MIT](LICENSE).
