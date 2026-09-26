import QtQuick
import qs.Ui as Ui

// Use the same theme-aware control as Omarchy's Agent panel.
Ui.Button {
    bordered: true
    focusable: true
    opacity: enabled ? 1 : 0.45
}
