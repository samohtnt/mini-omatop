import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
  name: "CpuRows"
  when: windowShown
  Component { id: component; Plugin.CpuStrip { width: 800; height: implicitHeight; reducedMotion: true } }

  function samples(count) {
    var result = []
    for (var i = 0; i < count; i++) result.push({id: i, usage: i === 0 ? 100 : 0})
    return result
  }

  function test_toggle_releases_row() {
    var strip = createTemporaryObject(component, this, {cpu: 25, cpuLogical: samples(8)})
    compare(strip.height, 3)
    compare(findChild(strip, "logicalRow").item, null)
    strip.showLogicalCpu = true
    compare(strip.height, 6)
    compare(findChild(strip, "totalCpu").y, 3)
    compare(findChild(strip, "logicalCpu0").height, 3)
    compare(findChild(findChild(strip, "logicalCpu0"), "meterItem0").displayedAmount, 1)
    compare(findChild(findChild(strip, "totalCpu"), "meterItem0").displayedAmount, 0.25)
    strip.showLogicalCpu = false
    compare(strip.height, 3)
    compare(findChild(strip, "logicalRow").item, null)
    compare(findChild(strip, "totalCpu").y, 0)
  }

  function test_small_monitor_restores_single_pixel_row() {
    var strip = createTemporaryObject(component, this, {singleRowHeight: 1})
    compare(strip.height, 1)
    strip.showLogicalCpu = true
    compare(strip.height, 6)
    compare(findChild(strip, "totalCpu").height, 3)
    strip.showLogicalCpu = false
    compare(strip.height, 1)
  }

  function test_adapts_counts_and_resizes() {
    var strip = createTemporaryObject(component, this, {showLogicalCpu: true})
    for (var count of [1, 2, 8, 16, 64, 128]) {
      strip.cpuLogical = samples(count)
      var last = findChild(strip, "logicalCpu" + (count - 1))
      verify(last !== null)
      compare(last.x + last.width, strip.width)
      compare(findChild(strip, "logicalCpu" + count), null)
      strip.width = 37
      verify(last.width >= 0)
      compare(last.x + last.width, 37)
      strip.width = 800
    }
    strip.cpuLogical = []
    compare(findChild(strip, "logicalCpu0"), null)
  }

  function test_samples_update_without_recreating_meters() {
    var strip = createTemporaryObject(component, this, {showLogicalCpu: true, cpuLogical: samples(8)})
    var first = findChild(strip, "logicalCpu0")
    strip.cpuLogical = [{id: 0, usage: 50}].concat(samples(8).slice(1))
    compare(findChild(strip, "logicalCpu0"), first)
    compare(findChild(first, "meterItem0").displayedAmount, 0.5)
    strip.reducedMotion = false
    strip.cpuLogical = samples(8)
    compare(findChild(first, "meterItem0").peakOpacity, 0)
  }

  function test_replaced_cpu_does_not_inherit_activity() {
    var strip = createTemporaryObject(component, this, {
      showLogicalCpu: true,
      cpuLogical: [{id: 0, usage: 100}]
    })
    compare(findChild(findChild(strip, "logicalCpu0"), "meterItem0").displayedAmount, 1)
    strip.reducedMotion = false
    strip.cpuLogical = [{id: 4, usage: null}]
    var replacement = findChild(strip, "logicalCpu0")
    compare(replacement.modelData, 4)
    compare(findChild(replacement, "meterItem0").displayedAmount, 0)
  }
}
