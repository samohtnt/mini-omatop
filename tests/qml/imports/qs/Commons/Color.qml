pragma Singleton
import QtQuick
QtObject {
  property color foreground: "white"
  property color muted: "gray"
  property color accent: "gold"
  property QtObject bar: QtObject {
    property color text: "white"
    property color active: "red"
  }
}
