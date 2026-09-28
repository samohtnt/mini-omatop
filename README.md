# mini-omatop

A super-minimal Omarchy plugin with one meter on each screen edge: CPU at the top, RAM on the left, root filesystem on the right, and network at the bottom.

```
                 ← CPU →
               ┌────────┐
         RAM ↑  │ screen │  DISK ↑
               └────────┘
              ← UP / DOWN →
```

Each monitor gets 1-pixel meters below 1200 logical pixels of height, or 3-pixel meters at 1200 and above. CPU grows outward from the horizontal center; RAM and root filesystem grow upward from the bottom edge.

The bottom network meter is one split bar. Upload grows leftward from the center, and download grows rightward. The two halves share a decaying peak, so their lengths show the relative rates. The idle track and panel background are transparent; traffic fills and fading peak marks appear when data moves.

The other three edge strips use the bar's background color. Meter fills use the active Omarchy theme: accent for CPU and download, bar text for RAM and upload, and muted for filesystem. As usage rises, each fill blends toward the theme's bar active color. Clicks pass through.

Colors are bound to Omarchy's live theme palette, so a theme switch updates the fills, tracks, peak marks, and bar-matched backgrounds without restarting the shell.

Changes smaller than one logical pixel are accumulated before starting another fill animation. Empty and full readings always apply. Set `MINI_OMATOP_REDUCED_MOTION=1` in the shell environment and restart the shell to use immediate fills without peak fades or disk flashes.

The fills rise smoothly over 280 ms and fall over 900 ms. A thin theme-colored high-water mark stays at the latest peak for 1.4 seconds, then fades over 4.2 seconds. The top CPU bar shows the mark at both ends of its center-out fill; each network half shows one mark at its outer end, and RAM shows it at the upper end.

The top nine pixels of the filesystem usage fill flash when the root filesystem's block device completes reads or writes. If `/` is on a network or virtual filesystem without a local block device, usage still works but the I/O flash is unavailable.

## Install on Omarchy

mini-omatop is a git repo with `manifest.json` at the root. From a clone of this repository:

```sh
omarchy plugin add /path/to/mini-omatop --enable
```

Or from a published git URL:

```sh
omarchy plugin add https://github.com/samohtnt/mini-omatop.git --enable
```

The installer clones into `~/.config/omarchy/plugins/troy.mini-omatop`, validates the manifest, and enables the panel. `keepLoaded` mounts it for the session, so the meters appear as soon as the shell loads the plugin.

To keep windows clear of all four strips, add `reserved_area` to each monitor's existing `hl.monitor` rule in `~/.config/hypr/monitors.lua`, preserving its mode, position, and scale. Use 3 pixels on every edge for monitors at least 1200 logical pixels tall:

```lua
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto",
  reserved_area = { top = 3, bottom = 3, left = 3, right = 3 } })
```

Use `{ top = 1, bottom = 1, left = 1, right = 1 }` for monitors below 1200 logical pixels tall. The empty output matches monitors without a more specific rule. If your configuration has output-specific rules, set `reserved_area` on each rule to match that monitor's meter thickness. Scale settings can change a monitor's logical height.

Hyprland places a top bar below the CPU strip and keeps tiled windows clear of the side and bottom strips.

If the strip is missing after enable:

```sh
omarchy-shell shell rescanPlugins
omarchy-restart-shell
```

### Install by hand

```sh
mkdir -p ~/.config/omarchy/plugins
cp -r . ~/.config/omarchy/plugins/troy.mini-omatop
omarchy-shell shell rescanPlugins
omarchy plugin enable troy.mini-omatop
```

Do not put a symlink in the plugin folder. Omarchy rejects plugins that contain symlinks.

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

## What it reads

| Meter | Source |
| --- | --- |
| CPU | `/proc/stat` idle/total deltas |
| RAM | `/proc/meminfo` (`MemTotal` − `MemAvailable`) |
| Download / upload | `/proc/net/dev` receive and transmit bytes on IPv4/IPv6 default-route interfaces, or all non-loopback interfaces when there is no default route; shared decaying peak (1 MB/s floor) |
| Root filesystem | `os.statvfs("/")`, used space as a percentage of used plus user-available space |
| Root disk activity | `/proc/self/mountinfo` identifies the root block device; `/proc/diskstats` reports completed reads and writes |

CPU, RAM, traffic counters, and disk activity update every second. Default routes are cached for at most five seconds and refreshed immediately when interfaces appear or disappear; filesystem capacity is refreshed every 30 seconds. A route change between existing interfaces can take up to five seconds to appear.

No extra packages. Python 3 is used as a long-running sampler inside `omarchy-shell`. Plugins run unsandboxed in that process — read the files before you enable them.

## Develop

```sh
python3 -m unittest discover -s tests -v
```

On an Omarchy machine, after copying into `~/.config/omarchy/plugins/troy.mini-omatop`, saving a QML file reloads the plugin. You can also force it:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/troy.mini-omatop
omarchy-shell shell rescanPlugins
```

Animation regression tests use Qt 6 Quick Test with a test-only palette:

```sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import tests/qml/imports
```
