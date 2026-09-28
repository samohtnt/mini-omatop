import QtQuick
import QtTest
import "../.." as Plugin

TestCase {
  name: "MeterAnimation"
  when: windowShown
  Component { id: component; Plugin.MeterStrip { width: 100; height: 3; reducedMotion: true } }
  function make(properties) {
    var meter = createTemporaryObject(component, this, properties || {})
    verify(meter !== null)
    return meter
  }
  function test_accumulated_changes_and_endpoints() {
    var meter = make({cpu: 50})
    var item = findChild(meter, "meterItem0")
    compare(item.displayedAmount, 0.5)
    meter.cpu = 50.4
    compare(item.displayedAmount, 0.5)
    meter.cpu = 51.2
    compare(item.displayedAmount, 0.512)
    meter.cpu = 99.8
    meter.cpu = 100
    compare(item.displayedAmount, 1)
    meter.cpu = 0.2
    meter.cpu = 0
    compare(item.displayedAmount, 0)
  }
  function test_vertical_extent() {
    var meter = make({meter: "ram", vertical: true, width: 3, height: 200, ram: 50})
    var item = findChild(meter, "meterItem0")
    meter.ram = 50.6
    compare(item.displayedAmount, 0.506)
  }
  function test_network_halves() {
    var meter = make({meter: "network", up: 50, down: 25})
    var item = findChild(meter, "meterItem0")
    meter.up = 51
    compare(item.displayedAmount, 0.5)
    meter.up = 52.1
    compare(item.displayedAmount, 0.521)
    compare(findChild(meter, "meterItem1").displayedAmount, 0.25)
  }
  function test_reduced_motion_stops_animation() {
    var meter = make({reducedMotion: false, cpu: 60})
    var item = findChild(meter, "meterItem0")
    meter.reducedMotion = true
    compare(item.displayedAmount, 0.6)
    compare(item.peakOpacity, 0)
    meter.cpu = 80
    compare(item.displayedAmount, 0.8)
  }
  function test_reduced_motion_disables_flash() {
    var meter = make({meter: "disk", disk: 50})
    meter.diskPulse = 1
    wait(100)
    compare(findChild(meter, "meterItem0").diskFlashOpacity, 0)
  }
  function test_disabling_peaks_clears_existing_marker() {
    var meter = make({reducedMotion: false, cpu: 60})
    var item = findChild(meter, "meterItem0")
    compare(item.peakOpacity, 0.95)
    meter.showPeaks = false
    compare(item.peakOpacity, 0)
    compare(item.peakAmount, 0)
    meter.cpu = 80
    compare(item.peakOpacity, 0)
  }
}
