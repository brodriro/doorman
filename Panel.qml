import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PresenceModel.js" as Presence

// Bar icon with the number of other devices online, and a popup listing who
// is on the network, who was seen before, and recent joins and leaves. All
// state lives in Service.qml (one per shell); this file only draws it.
Panel {
  id: root
  moduleName: "xaiovz.doorman"
  ipcTarget: "xaiovz.doorman"
  manageIpc: true

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("xaiovz.doorman") : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var network: service ? service.network : null
  readonly property var devices: service ? service.devices : []
  readonly property var online: devices.filter(function(d) { return d.present })
  readonly property var offline: devices.filter(function(d) { return !d.present })
  readonly property var activity: service ? service.history.slice(0, 12) : []
  readonly property int othersOnline: online.filter(function(d) { return !d.isSelf && !d.isGateway }).length
  readonly property bool alerting: !!service && service.unseenNew > 0

  property string editingMac: ""
  property double nowMs: Date.now()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The service has no settings of its own: the widget's shell.json entry
  // is the single source, pushed in from here.
  Binding {
    target: root.service
    when: !!root.service
    property: "settings"
    value: root.settings
  }

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      editingMac = ""
      if (service) service.markSeen()
    }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  function refreshNow() { if (service) service.refresh() }

  function displayName(d) {
    if (d.isSelf && !d.alias) return strings.t("device.thisComputer")
    if (d.isGateway && !d.alias && !d.name) return strings.t("device.router")
    return Presence.displayName(d) || strings.t("device.unknown")
  }

  function formatTime(ts) {
    if (!ts) return ""
    var date = new Date(ts * 1000)
    var locale = Qt.locale(Commons.I18n.formatLocale)
    var today = new Date(nowMs)
    var sameDay = date.toDateString() === today.toDateString()
    return sameDay ? date.toLocaleTimeString(locale, "HH:mm") : date.toLocaleString(locale, "d MMM HH:mm")
  }

  function networkTitle() {
    if (!network) return strings.t("title.disconnected")
    return network.ssid || strings.t("title.wired")
  }

  function networkMeta() {
    if (!network) return service ? service.lastError : ""
    var parts = [network.subnet || "", network.iface || ""]
    if (service && service.scanning) parts.push(strings.t("panel.scanning"))
    else if (service && service.lastScanMs > 0) parts.push(strings.t("panel.updated").arg(formatTime(service.lastScanMs / 1000)))
    return parts.filter(function(p) { return p !== "" }).join(" · ")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.network && root.network.wireless ? "󰖩" : "󰛳"
    labelText: root.service && root.network ? String(root.othersOnline) + (root.alerting ? " +" + root.service.unseenNew : "") : ""
    active: root.alerting
    tooltipText: root.networkTitle()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingMac !== ""

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy * Style.space(48)))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: root.networkTitle()
            meta: root.networkMeta()
            detail: root.network ? strings.tn("panel.devices", root.online.length).arg(Commons.I18n.formatNumber(root.online.length)) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: button.text
                color: root.alerting ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: strings.t("action.refresh")
                foreground: root.foreground
                enabled: !!root.service && !root.service.scanning
                onClicked: root.refreshNow()
              }
            }
          }

          Text {
            visible: !!root.service && root.devices.length === 0
            width: parent.width
            topPadding: Style.space(16)
            textFormat: Text.PlainText
            text: strings.t("empty.devices")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          PanelSeparator { visible: root.online.length > 0; width: parent.width; foreground: root.foreground }
          PanelSectionHeader {
            visible: root.online.length > 0
            text: strings.t("section.online")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: root.online
            delegate: deviceRow
          }

          PanelSeparator { visible: root.offline.length > 0; width: parent.width; foreground: root.foreground }
          PanelSectionHeader {
            visible: root.offline.length > 0
            text: strings.t("section.offline")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: root.offline
            delegate: deviceRow
          }

          PanelSeparator { visible: root.activity.length > 0; width: parent.width; foreground: root.foreground }
          PanelSectionHeader {
            visible: root.activity.length > 0
            text: strings.t("section.activity")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Repeater {
            model: root.activity
            delegate: Row {
              required property var modelData
              width: column.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: modelData.type === "left" ? "−" : "+"
                color: modelData.type === "left" ? root.dim : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width - Style.space(70)
                elide: Text.ElideRight
                text: (modelData.type === "left" ? strings.t("event.left")
                       : modelData.returning ? strings.t("event.returned")
                       : strings.t("event.joined")).arg(modelData.name || modelData.ip || modelData.mac)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                textFormat: Text.PlainText
                text: root.formatTime(modelData.ts)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: deviceRow

    Item {
      id: row
      required property var modelData
      readonly property bool isNew: !!root.service && root.service.newMacs[modelData.mac] === true
      readonly property bool editing: root.editingMac === modelData.mac

      width: column.width
      implicitHeight: rowColumn.implicitHeight + Style.space(6)
      opacity: modelData.present ? 1 : 0.6

      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        visible: row.isNew
        radius: Style.cornerRadius
        color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)
      }

      Column {
        id: rowColumn
        anchors.left: parent.left
        anchors.right: renameButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          visible: !row.editing
          width: parent.width
          textFormat: Text.PlainText
          text: root.displayName(row.modelData)
          color: row.isNew ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        TextField {
          id: aliasField
          visible: row.editing
          width: parent.width
          placeholderText: strings.t("device.renamePlaceholder")
          maximumLength: 64
          foreground: root.foreground
          onVisibleChanged: if (visible) {
            text = row.modelData.alias || row.modelData.name || ""
            forceActiveFocus()
            selectAll()
          }
          onAccepted: {
            if (root.service) root.service.setAlias(row.modelData.mac, text)
            root.editingMac = ""
            keyCatcher.forceActiveFocus()
          }
          Keys.onEscapePressed: {
            root.editingMac = ""
            keyCatcher.forceActiveFocus()
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            var d = row.modelData
            var parts = [d.ip || "", d.mac]
            if (d.isGateway && (d.alias || d.name)) parts.push(strings.t("device.router"))
            if (d.randomMac) parts.push(strings.t("device.private"))
            if (!d.present) parts.push(strings.t("device.lastSeen").arg(root.formatTime(d.lastSeen)))
            return parts.filter(function(p) { return p !== "" }).join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: renameButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: row.editing ? "󰅖" : "󰏫"
        tooltipText: strings.t("device.rename")
        foreground: root.foreground
        onClicked: root.editingMac = row.editing ? "" : row.modelData.mac
      }
    }
  }
}
