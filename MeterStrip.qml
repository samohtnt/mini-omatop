pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

Item {
  id: root

  property string meter: "cpu"
  property bool vertical: false
  property bool reducedMotion: false
  property bool showPeaks: true
  property real cpu: 0
  property real ram: 0
  property real down: 0
  property real up: 0
  property real disk: 0
  property int diskPulse: 0

  readonly property bool networkOnly: meter === "network"
  readonly property bool peaksEnabled: showPeaks && meter !== "disk"
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
        readonly property bool upload: root.networkOnly && index === 0
        readonly property real value: {
          if (root.networkOnly) return upload ? root.up : root.down
          if (root.meter === "ram") return root.ram
          if (root.meter === "disk") return root.disk
          return root.cpu
        }
        readonly property color baseColor: {
          if (root.meter === "disk") return Color.muted
          if (root.meter === "ram" || upload) return Color.bar.text
          return Color.accent
        }
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

        function clearPeak() {
          peakHold.stop()
          peakFade.stop()
          peakAmount = 0
          peakOpacity = 0
        }

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

          if (root.peaksEnabled && targetAmount > 0 && (targetAmount > peakAmount || peakOpacity === 0)) {
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
          function onPeaksEnabledChanged() {
            if (!root.peaksEnabled)
              meterItem.clearPeak()
          }
          function onReducedMotionChanged() {
            if (root.reducedMotion) {
              fillAnimation.stop()
              meterItem.clearPeak()
              diskFlash.stop()
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
          x: {
            if (root.vertical) return 0
            if (root.networkOnly) return meterItem.upload ? meterItem.width - width : 0
            return (meterItem.width - width) / 2
          }
          y: root.vertical ? meterItem.height - height : 0
          width: root.vertical ? meterItem.width : meterItem.width * meterItem.displayedAmount
          height: root.vertical ? meterItem.height * meterItem.displayedAmount : meterItem.height
          color: root.fillColor(meterItem.baseColor, Color.bar.active, meterItem.displayedAmount * 100)

          Rectangle {
            width: usageFill.width
            height: Math.min(9, usageFill.height)
            visible: root.meter === "disk"
            color: Color.bar.text
            opacity: meterItem.diskFlashOpacity
          }
        }

        Rectangle {
          visible: root.peaksEnabled && root.vertical
          x: 0
          y: Math.max(0, Math.min(meterItem.height - height, meterItem.height * (1 - meterItem.peakAmount) - height / 2))
          width: meterItem.width
          height: 2
          color: Color.bar.text
          opacity: meterItem.peakOpacity
        }

        Repeater {
          model: root.vertical || !root.peaksEnabled ? 0 : root.networkOnly ? 1 : 2

          Rectangle {
            required property int index
            readonly property real position: {
              if (root.networkOnly)
                return meterItem.upload ? 1 - meterItem.peakAmount : meterItem.peakAmount
              return (1 + (index === 0 ? -1 : 1) * meterItem.peakAmount) / 2
            }
            x: Math.max(0, Math.min(meterItem.width - width, meterItem.width * position - width / 2))
            y: 0
            width: 2
            height: meterItem.height
            color: Color.bar.text
            opacity: meterItem.peakOpacity
          }
        }
      }
    }
  }
}
