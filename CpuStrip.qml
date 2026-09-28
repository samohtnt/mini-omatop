pragma ComponentBehavior: Bound

import QtQuick

Item {
  id: root

  property bool showLogicalCpu: false
  property bool reducedMotion: false
  property int singleRowHeight: 3
  property real cpu: 0
  property var cpuLogical: []
  readonly property int rowHeight: 3
  readonly property int slotGap: 2
  property var cpuIds: []

  implicitHeight: showLogicalCpu ? 2 * rowHeight : singleRowHeight

  onCpuLogicalChanged: {
    var nextIds = cpuLogical.map(function(cpu) { return cpu.id })
    var changed = nextIds.length !== cpuIds.length || nextIds.some(function(id, index) {
      return id !== root.cpuIds[index]
    })
    // Rebuild only when the topology changes, never on ordinary usage updates.
    // A new CPU must not inherit the previous occupant's fill animation.
    if (changed)
      cpuIds = nextIds
  }

  Loader {
    id: logicalRow
    objectName: "logicalRow"
    active: root.showLogicalCpu
    anchors { left: parent.left; right: parent.right; top: parent.top }
    height: root.rowHeight
    sourceComponent: Item {
      Repeater {
        model: root.cpuIds
        MeterStrip {
          required property int index
          required property int modelData
          objectName: "logicalCpu" + index
          readonly property int slotCount: Math.max(1, root.cpuIds.length)
          readonly property int slotStart: Math.floor(index * logicalRow.width / slotCount)
          readonly property int slotEnd: Math.floor((index + 1) * logicalRow.width / slotCount)
          readonly property var sample: root.cpuLogical[index]
          // Narrow displays/high CPU counts shrink the gap before sacrificing fills.
          readonly property int gap: index === slotCount - 1 ? 0
            : Math.min(root.slotGap, Math.max(0, slotEnd - slotStart - 1))

          x: slotStart
          width: Math.max(0, slotEnd - slotStart - gap)
          height: root.rowHeight
          opacity: 0.7
          reducedMotion: root.reducedMotion
          showPeaks: false
          cpu: sample && sample.id === modelData ? Number(sample.usage) || 0 : 0
        }
      }
    }
  }

  MeterStrip {
    objectName: "totalCpu"
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    height: root.showLogicalCpu ? root.rowHeight : root.singleRowHeight
    reducedMotion: root.reducedMotion
    cpu: root.cpu
  }
}
