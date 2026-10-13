import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Not a visible panel. The popup is Panel.qml (its own window); this item only exists
// because the shell's Panel type is what exposes the bar's colours (barForeground,
// barBackground), which the popup uses when `bar` does not carry them itself.
Panel {
  id: root
  moduleName: "io.github.qempexe.omaotp"
  manageIpc: false
}
