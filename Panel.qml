import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: true
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

  Sampler { id: stats; active: root.showing }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.showing
        color: Color.bar.background
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: root.edgePixels(modelData)
        mask: Region {}
        WlrLayershell.namespace: "mini-omatop-cpu"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; left: true; right: true }
        MeterStrip { anchors.fill: parent; reducedMotion: root.reducedMotion; meter: "cpu"; cpu: stats.cpu }
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
        MeterStrip { anchors.fill: parent; reducedMotion: root.reducedMotion; meter: "ram"; vertical: true; ram: stats.ram }
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
        MeterStrip { anchors.fill: parent; reducedMotion: root.reducedMotion; meter: "disk"; vertical: true; disk: stats.disk; diskPulse: stats.diskPulse }
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
