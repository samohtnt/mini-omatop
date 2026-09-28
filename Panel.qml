pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: true
  property var settings: ({})
  property bool settingsLoaded: false
  readonly property string pluginId: "troy.mini-omatop"
  readonly property bool showLogicalCpu: settings.showLogicalCpu === true
  readonly property bool reducedMotion: Quickshell.env("MINI_OMATOP_REDUCED_MOTION") === "1"

  readonly property bool barHidden: !!(root.shell && root.shell.bar && root.shell.bar.barHidden === true)
  readonly property bool showing: opened && !barHidden

  function edgePixels(display) {
    return display.height >= 1200 ? 3 : 1
  }

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  // Panels do not receive inline settings from the host, so watch our entry.
  // Writes go through the shell to preserve the rest of its configuration.
  FileView {
    id: configFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoadFailed: root.settingsLoaded = false
    onLoaded: {
      try {
        var entries = JSON.parse(configFile.text()).plugins
        if (!Array.isArray(entries))
          throw new Error("plugins must be an array")
        var entry = entries.find(function(item) { return item && item.id === root.pluginId })
        root.settings = entry || ({})
        root.settingsLoaded = !!entry
      } catch (e) {
        root.settingsLoaded = false
        console.warn("mini-omatop: could not read settings", e)
      }
    }
  }

  // omarchy-shell shell call troy.mini-omatop logicalCpu on|off|toggle|status
  function logicalCpu(action) {
    if (["on", "off", "toggle", "status"].indexOf(action) < 0)
      return "expected on, off, toggle, or status"
    if (!settingsLoaded)
      return "settings unavailable"
    if (action === "status")
      return showLogicalCpu ? "on" : "off"

    var enabled = action === "toggle" ? !showLogicalCpu : action === "on"
    if (enabled === showLogicalCpu)
      return enabled ? "on" : "off"
    if (!shell || typeof shell.updateEntryInline !== "function")
      return "settings unavailable"

    var next = Object.assign({}, settings, { showLogicalCpu: enabled })
    if (!shell.updateEntryInline(pluginId, next))
      return "could not save settings"
    root.settings = next
    return enabled ? "on" : "off"
  }

  Sampler { id: stats; active: root.showing }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: cpuWindow
        required property var modelData
        screen: modelData
        visible: root.showing
        color: Color.bar.background
        exclusionMode: ExclusionMode.Auto
        implicitHeight: cpuStrip.implicitHeight
        mask: Region {}
        WlrLayershell.namespace: "mini-omatop-cpu"
        // Reserve the physical top edge before the menubar is arranged.
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; left: true; right: true }
        CpuStrip {
          id: cpuStrip
          anchors.fill: parent
          singleRowHeight: root.edgePixels(cpuWindow.modelData)
          reducedMotion: root.reducedMotion
          showLogicalCpu: root.showLogicalCpu
          cpu: stats.cpu
          cpuLogical: stats.cpuLogical
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.showing
        color: Color.bar.background
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.edgePixels(modelData)
        mask: Region {}
        WlrLayershell.namespace: "mini-omatop-ram"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true }
        MeterStrip {
          anchors.fill: parent
          reducedMotion: root.reducedMotion
          meter: "ram"
          vertical: true
          ram: stats.ram
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.showing
        color: Color.bar.background
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.edgePixels(modelData)
        mask: Region {}
        WlrLayershell.namespace: "mini-omatop-disk"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; right: true }
        MeterStrip {
          anchors.fill: parent
          reducedMotion: root.reducedMotion
          meter: "disk"
          vertical: true
          disk: stats.disk
          diskPulse: stats.diskPulse
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.showing
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: root.edgePixels(modelData)
        mask: Region {}
        WlrLayershell.namespace: "mini-omatop-network"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { bottom: true; left: true; right: true }
        MeterStrip {
          anchors.fill: parent
          reducedMotion: root.reducedMotion
          meter: "network"
          down: stats.down
          up: stats.up
        }
      }
    }
  }
}
