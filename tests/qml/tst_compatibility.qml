import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
  id: testCase
  name: "DisplayCompatibility"
  when: windowShown
  visible: true
  width: 1200
  height: 50

  Component {
    id: cpuComponent
    Plugin.CpuStrip {
      height: implicitHeight
      showLogicalCpu: true
      reducedMotion: true
    }
  }

  Component {
    id: backgroundComponent
    Rectangle { width: 400; height: 6; color: "black" }
  }

  function test_layout_data() {
    var cases = []
    for (var width of [320, 720, 1080, 1366, 1920, 2560, 3440, 3840, 5120, 7680]) {
      for (var count of [1, 8, 24, 64, 256, 512])
        cases.push({tag: width + "px-" + count + "cpus", width: width, count: count})
    }
    return cases
  }

  function test_layout(data) {
    var cpus = []
    for (var i = 0; i < data.count; i++) cpus.push({id: i * 2, usage: 50})
    var strip = createTemporaryObject(cpuComponent, this, {width: data.width, cpuLogical: cpus})
    verify(strip !== null)
    compare(strip.height, 6)
    var previousEnd = 0
    for (var slot = 0; slot < data.count; slot++) {
      var meter = findChild(strip, "logicalCpu" + slot)
      verify(isFinite(meter.x) && isFinite(meter.width))
      verify(meter.width >= 0)
      verify(meter.x >= previousEnd)
      previousEnd = meter.x + meter.width
      verify(previousEnd <= data.width)
    }
    compare(previousEnd, data.width)
  }

  function test_rendered_rows_and_gaps() {
    var background = createTemporaryObject(backgroundComponent, this)
    var strip = createTemporaryObject(cpuComponent, background, {
      width: 400,
      cpu: 50,
      cpuLogical: [{id: 0, usage: 100}, {id: 1, usage: 0},
                   {id: 2, usage: 100}, {id: 3, usage: 0}]
    })
    verify(waitForRendering(strip), "CPU rows must reach the renderer")
    // Capture enough scene space even when software grabs lose DPR metadata.
    var picture = grabImage(testCase)
    var scale = Screen.devicePixelRatio
    function red(x, y) { return picture.red(Math.floor(x * scale), Math.floor(y * scale)) }
    verify(red(50, 1) > red(150, 1), "busy logical CPU must be brighter than idle")
    verify(red(50, 1) > red(99, 1), "logical CPU gap must stay visible")
    verify(red(200, 4) > red(20, 4), "total CPU fill must be centered in the lower row")
  }
}
