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
  // Flagged devices get their own section (design C), so they come out of the
  // normal present/absent lists.
  readonly property var flagged: devices.filter(function(d) { return d.blocked })
  readonly property var online: devices.filter(function(d) { return d.present && !d.blocked })
  readonly property var offline: devices.filter(function(d) { return !d.present && !d.blocked })
  readonly property int presentCount: devices.filter(function(d) { return d.present }).length
  readonly property var activity: service ? service.history.slice(0, 12) : []
  readonly property int othersOnline: online.filter(function(d) { return !d.isSelf && !d.isGateway }).length
  readonly property bool alerting: !!service && service.unseenNew > 0

  readonly property color neutral: Qt.darker(foreground, 1.25)
  readonly property int scanEverySec: Number(settings && settings.scanIntervalSec) || 60
  readonly property int graceSec: Number(settings && settings.absenceGraceSec) || 300

  // A nerd-font glyph per device kind (all verified present in the theme font).
  function typeIcon(d) {
    if (d.blocked) return "󱂩"       // ban
    if (d.isGateway) return "󰑩"     // router
    if (d.isSelf) return "󰍹"        // this monitor
    if (d.randomMac) return "󰄜"     // phone (private MACs are usually phones)
    return "󰌢"                       // generic laptop/device
  }

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

  // A small tinted rounded label. `big` is the counter-chip size (under the
  // hero); the default is the badge size used on device rows. Colours come
  // from live theme roles only (accent / urgent / neutral), never hardcoded.
  component Pill: Rectangle {
    id: pill
    property string label: ""
    property color tone: root.neutral
    property bool big: false
    readonly property int padX: big ? Style.space(10) : Style.space(7)
    readonly property int padY: big ? Style.space(5) : Style.space(3)
    implicitWidth: pillLabel.implicitWidth + padX * 2
    implicitHeight: pillLabel.implicitHeight + padY * 2
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.14)
    Text {
      id: pillLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: pill.label
      color: pill.tone
      font.family: root.fontFamily
      font.pixelSize: pill.big ? Style.font.bodySmall : Style.font.caption
      font.bold: true
    }
  }

  // The leading rounded icon tile on each device row (and the hero).
  component IconTile: Rectangle {
    id: tile
    property string glyph: ""
    property color tone: root.foreground
    property real diameter: Style.space(34)
    implicitWidth: diameter
    implicitHeight: diameter
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : diameter / 2
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.12)
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: tile.glyph
      color: tile.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.iconLarge
    }
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
              IconTile {
                glyph: button.text
                tone: root.alerting ? root.urgent : root.accent
                diameter: Style.space(40)
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

          // Counter chips (design A): a glanceable summary under the hero.
          Row {
            width: parent.width
            visible: !!root.network && root.devices.length > 0
            spacing: Style.space(8)
            Pill { big: true; tone: root.accent; label: strings.t("chip.online").arg(root.presentCount) }
            Pill { big: true; visible: root.alerting; tone: root.urgent; label: strings.t("chip.new").arg(root.service.unseenNew) }
            Pill { big: true; visible: root.offline.length > 0; tone: root.neutral; label: strings.t("chip.absent").arg(root.offline.length) }
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

          // Flagged devices first (design C): the thing the user acts on.
          PanelSeparator { visible: root.flagged.length > 0; width: parent.width; foreground: root.foreground }
          PanelSectionHeader {
            visible: root.flagged.length > 0
            text: strings.t("section.flagged").toUpperCase() + " · " + root.flagged.length
            foreground: root.urgent
            fontFamily: root.fontFamily
          }
          Repeater {
            model: root.flagged
            delegate: deviceRow
          }

          PanelSeparator { visible: root.online.length > 0; width: parent.width; foreground: root.foreground }
          PanelSectionHeader {
            visible: root.online.length > 0
            text: strings.t("section.online").toUpperCase() + " · " + root.online.length
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
            text: strings.t("section.offline").toUpperCase() + " · " + root.offline.length
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
            text: strings.t("section.activity").toUpperCase()
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

          // Footer (design A): the cadence, so the counts have context.
          PanelSeparator { visible: root.devices.length > 0; width: parent.width; foreground: root.foreground }
          Text {
            visible: root.devices.length > 0
            width: parent.width
            textFormat: Text.PlainText
            text: strings.t("panel.cadence").arg(root.scanEverySec).arg(Math.round(root.graceSec / 60))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
      readonly property bool blocked: modelData.blocked === true
      // Only real peers can be flagged — never this machine or the router.
      readonly property bool flaggable: !modelData.isSelf && !modelData.isGateway

      // Tone for this row's icon tile and accents.
      readonly property color tone: blocked ? root.urgent : isNew ? root.urgent : root.foreground

      width: column.width
      implicitHeight: Math.max(tile.height, rowColumn.implicitHeight) + Style.space(8)
      opacity: modelData.present ? 1 : 0.6

      // Card background: urgent tint for new/flagged rows, plus a solid border
      // on flagged ones so they read as the alert card from design C.
      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        visible: row.isNew || row.blocked
        radius: Style.cornerRadius
        color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, row.blocked ? 0.16 : 0.10)
        border.width: row.blocked ? Math.max(1, Style.space(1)) : 0
        border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.55)
      }

      IconTile {
        id: tile
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: Style.space(1)
        glyph: root.typeIcon(row.modelData)
        tone: row.tone
      }

      Column {
        id: rowColumn
        anchors.left: tile.right
        anchors.leftMargin: Style.space(10)
        anchors.right: actions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Row {
          visible: !row.editing
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + Style.space(8) : 0))
            textFormat: Text.PlainText
            text: root.displayName(row.modelData)
            color: (row.isNew || row.blocked) ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          // One badge, most salient state first.
          Pill {
            id: badge
            anchors.verticalCenter: parent.verticalCenter
            readonly property var spec: {
              var d = row.modelData
              if (d.blocked) return { label: strings.t("device.blocked"), tone: root.urgent }
              if (row.isNew) return { label: strings.t("badge.new"), tone: root.urgent }
              if (d.isGateway) return { label: strings.t("device.router"), tone: root.neutral }
              if (d.isSelf) return { label: strings.t("badge.you"), tone: root.accent }
              if (d.randomMac) return { label: strings.t("device.private"), tone: root.neutral }
              return null
            }
            visible: !!spec
            label: spec ? spec.label : ""
            tone: spec ? spec.tone : root.neutral
          }
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
            if (!d.present) parts.push(strings.t("device.lastSeen").arg(root.formatTime(d.lastSeen)))
            return parts.filter(function(p) { return p !== "" }).join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // Shown only once the user has flagged the device: the plugin cannot
        // disconnect it, so the action it points to is in the router.
        Text {
          visible: row.blocked
          width: parent.width
          topPadding: Style.space(2)
          textFormat: Text.PlainText
          text: strings.t("device.blockHint")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        // Copy the MAC for pasting into the router blocklist. Only useful once
        // flagged, so it stays hidden until then.
        PanelActionButton {
          visible: row.blocked
          iconText: "󰆏"
          tooltipText: strings.t("device.copyMac")
          foreground: root.foreground
          onClicked: if (root.service) root.service.copyMac(row.modelData.mac)
        }

        // Flag / unflag as an unauthorized device. Passive: it marks the row
        // and nothing more — blocking happens in the router, by hand.
        PanelActionButton {
          visible: row.flaggable
          iconText: row.blocked ? "󰞀" : "󰀦"
          tooltipText: row.blocked ? strings.t("device.unflag") : strings.t("device.flag")
          foreground: row.blocked ? root.urgent : root.foreground
          hoverColor: root.urgent
          onClicked: if (root.service) root.service.setBlocked(row.modelData.mac, !row.blocked)
        }

        PanelActionButton {
          id: renameButton
          iconText: row.editing ? "󰅖" : "󰏫"
          tooltipText: strings.t("device.rename")
          foreground: root.foreground
          onClicked: root.editingMac = row.editing ? "" : row.modelData.mac
        }
      }
    }
  }
}
