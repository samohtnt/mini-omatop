import QtQuick
import qs.Commons

Item {
  id: root

  property string meter: "cpu"
  property bool vertical: false
  property bool reducedMotion: false
  property real cpu: 0
  property real ram: 0
  property real down: 0
  property real up: 0
  property real disk: 0
  property int diskPulse: 0

  readonly property bool networkOnly: meter === "network"
  readonly property color trackColor: networkOnly ? "transparent" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)

  function fillColor(baseColor, hot, percent) {
    var p = Math.max(0, Math.min(100, Number(percent) || 0)) / 100
    return Qt.rgba(
      baseColor.r * (1 - p) + hot.r * p,
      baseColor.g * (1 - p) + hot.g * p,
      baseColor.b * (1 - p) + hot.b * p,
      0.95
    )
  }

  Row {
    id: meterRow
    anchors.fill: parent
    spacing: 0

    Repeater {
      model: root.networkOnly ? 2 : 1

      Rectangle {
        id: meterItem
        objectName: "meterItem" + index
        required property int index
        readonly property real value: root.networkOnly ? (index === 0 ? root.up : root.down)
          : root.meter === "ram" ? root.ram : root.meter === "disk" ? root.disk : root.cpu
        readonly property color baseColor: root.meter === "disk" ? Color.muted
          : root.meter === "ram" || (root.networkOnly && index === 0) ? Color.bar.text : Color.accent
        readonly property real targetAmount: {
          var amount = Math.max(0, Math.min(1, (Number(value) || 0) / 100))
          if (root.networkOnly && amount > 0 && meterRow.width > 0)
            amount = Math.max(amount, 2 / meterRow.width)
          return amount
        }
        readonly property int pulse: root.diskPulse
        property real displayedAmount: 0
        property real acceptedAmount: 0
        property real peakAmount: 0
        property real peakOpacity: 0
        property real diskFlashOpacity: 0
        property bool ready: false

        function applySample() {
          var extent = root.vertical ? height : width
          // Compare against the last accepted target so small changes accumulate.
          if (extent <= 0)
            return
          if (targetAmount !== 0 && targetAmount !== 1
              && Math.abs(targetAmount - acceptedAmount) * extent < 1)
            return
          if (targetAmount === acceptedAmount)
            return
          acceptedAmount = targetAmount
          fillAnimation.stop()
          if (root.reducedMotion) {
            displayedAmount = targetAmount
            return
          }
          fillAnimation.from = displayedAmount
          fillAnimation.to = targetAmount
          fillAnimation.duration = targetAmount > displayedAmount ? 280 : 900
          fillAnimation.start()

          if (root.meter !== "disk" && targetAmount > 0 && (targetAmount > peakAmount || peakOpacity === 0)) {
            peakAmount = targetAmount
            peakFade.stop()
            peakOpacity = 0.95
            peakHold.restart()
          }
        }

        Component.onCompleted: {
          ready = true
          applySample()
        }
        onWidthChanged: { if (ready) applySample() }
        onHeightChanged: { if (ready) applySample() }
        Connections {
          target: root
          function onReducedMotionChanged() {
            if (root.reducedMotion) {
              fillAnimation.stop()
              peakHold.stop()
              peakFade.stop()
              diskFlash.stop()
              meterItem.peakOpacity = 0
              meterItem.diskFlashOpacity = 0
              meterItem.acceptedAmount = meterItem.targetAmount
              meterItem.displayedAmount = meterItem.targetAmount
            }
          }
        }
        onTargetAmountChanged: {
          if (ready)
            applySample()
        }
        onPulseChanged: {
          if (ready && !root.reducedMotion && root.meter === "disk" && pulse > 0)
            diskFlash.restart()
        }

        width: root.networkOnly ? meterRow.width / 2 : meterRow.width
        height: meterRow.height
        color: root.trackColor

        NumberAnimation {
          id: fillAnimation
          target: meterItem
          property: "displayedAmount"
          easing.type: Easing.OutCubic
        }

        Timer {
          id: peakHold
          interval: 1400
          onTriggered: peakFade.start()
        }

        NumberAnimation {
          id: peakFade
          target: meterItem
          property: "peakOpacity"
          to: 0
          duration: 4200
          easing.type: Easing.OutCubic
        }

        SequentialAnimation {
          id: diskFlash
          NumberAnimation { target: meterItem; property: "diskFlashOpacity"; to: 1; duration: 90 }
          PauseAnimation { duration: 160 }
          NumberAnimation { target: meterItem; property: "diskFlashOpacity"; to: 0; duration: 700 }
        }

        Rectangle {
          id: usageFill
          x: root.vertical ? 0 : root.networkOnly ? (meterItem.index === 0 ? parent.width - width : 0) : (parent.width - width) / 2
          y: root.vertical ? parent.height - height : 0
          width: root.vertical ? parent.width : parent.width * parent.displayedAmount
          height: root.vertical ? parent.height * parent.displayedAmount : parent.height
          color: root.fillColor(parent.baseColor, Color.bar.active, parent.displayedAmount * 100)

          Rectangle {
            width: parent.width
            height: Math.min(9, parent.height)
            visible: root.meter === "disk"
            color: Color.bar.text
            opacity: meterItem.diskFlashOpacity
          }
        }

        Rectangle {
          visible: root.vertical && root.meter !== "disk"
          x: 0
          y: Math.max(0, Math.min(parent.height - height, parent.height * (1 - parent.peakAmount) - height / 2))
          width: parent.width
          height: 2
          color: Color.bar.text
          opacity: parent.peakOpacity
        }

        Repeater {
          model: root.vertical ? 0 : root.networkOnly ? 1 : 2

          Rectangle {
            required property int index
            x: Math.max(0, Math.min(parent.width - width,
                                    root.networkOnly
                                      ? (meterItem.index === 0 ? parent.width * (1 - parent.peakAmount) : parent.width * parent.peakAmount) - width / 2
                                      : parent.width * (1 + (index === 0 ? -1 : 1) * parent.peakAmount) / 2 - width / 2))
            y: 0
            width: 2
            height: parent.height
            color: Color.bar.text
            opacity: parent.peakOpacity
          }
        }
      }
    }
  }
}
