import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "nertwork.drawer"

  // Resolve underlying Bar instance when root.bar is a scoped PluginBarApi facade
  property var resolvedBar: null
  readonly property var hostBar: (root.bar && root.bar.barWidgetRegistry) ? root.bar : (resolvedBar || root.bar)

  function tryResolveHostBar() {
    if (root.bar && root.bar.barWidgetRegistry) {
      if (resolvedBar !== root.bar) resolvedBar = root.bar
      return true
    }
    for (var p = root.parent; p; p = p.parent) {
      var hosts = (p.pool && p.pool.hosts) ? p.pool.hosts : (p.hosts ? p.hosts : null)
      if (hosts) {
        for (var k in hosts) {
          var h = hosts[k]
          if (h && h.activeItem && h.activeItem.bar && h.activeItem.bar.barWidgetRegistry) {
            if (resolvedBar !== h.activeItem.bar) resolvedBar = h.activeItem.bar
            return true
          }
        }
      }
    }
    return false
  }

  Timer {
    id: hostBarResolveTimer
    interval: 50
    repeat: true
    running: !(root.hostBar && root.hostBar.barWidgetRegistry)
    onTriggered: root.tryResolveHostBar()
  }

  onBarChanged: tryResolveHostBar()
  onParentChanged: tryResolveHostBar()
  Component.onCompleted: {
    tryResolveHostBar()
    Qt.callLater(tryResolveHostBar)
  }

  // Settings & Configuration
  readonly property var defaultItems: [
    "omarchy.tailscale",
    "nertwork.agents",
    "omarchy.bluetooth",
    "omarchy.network",
    "omarchy.microphone"
  ]
  readonly property var configuredItems: {
    var s = root.settings
    var list = s && s.items ? s.items : setting("items", null)
    if (list instanceof Array && list.length > 0) return list
    return defaultItems
  }
  readonly property int animationDuration: Math.max(50, Math.min(2000, setting("animationDuration", 350)))
  readonly property string chevronPosition: setting("chevronPosition", "left")
  readonly property bool chevronOnLeft: chevronPosition !== "right"

  // State
  property bool defaultExpanded: setting("defaultExpanded", false)
  property bool expanded: defaultExpanded
  readonly property bool opened: expanded
  property real revealProgress: expanded ? 1.0 : 0.0

  Behavior on revealProgress {
    NumberAnimation {
      duration: root.animationDuration
      easing.type: Easing.OutCubic
    }
  }

  readonly property string chevronIcon: {
    if (chevronOnLeft) {
      return expanded ? "󰅁" : "󰅂"
    } else {
      return expanded ? "󰅂" : "󰅁"
    }
  }

  readonly property real contentExtent: layoutLoader.item ? layoutLoader.item.contentExtent : 0
  readonly property real revealExtent: Math.round(contentExtent * revealProgress)

  implicitWidth: root.vertical ? root.barSize : (layoutLoader.item ? layoutLoader.item.implicitWidth : Style.bar.iconSlot)
  implicitHeight: root.vertical ? (layoutLoader.item ? layoutLoader.item.implicitHeight : Style.bar.iconSlot) : root.barSize

  function toggleLocal() {
    expanded = !expanded
  }

  function expandLocal() {
    expanded = true
  }

  function collapseLocal() {
    expanded = false
  }

  function toggle() {
    toggleLocal()
  }

  function expand() {
    expandLocal()
  }

  function collapse() {
    collapseLocal()
  }

  function open() {
    expandLocal()
  }

  function close() {
    collapseLocal()
  }

  function isChildItem(item) {
    if (!item) return false
    var repeater = layoutLoader.item ? layoutLoader.item.repeater : null
    if (!repeater) return false
    for (var i = 0; i < repeater.count; i++) {
      var slot = repeater.itemAt(i)
      if (slot && slot.activeItem === item) return true
    }
    return false
  }

  // Auto-expand when a nested child popout opens
  Connections {
    target: root.hostBar
    ignoreUnknownSignals: true

    function onActivePopoutChanged() {
      if (root.hostBar && root.hostBar.activePopout && root.isChildItem(root.hostBar.activePopout)) {
        if (!root.expanded) {
          root.expandLocal()
        }
      }
    }
  }

  // Close child popouts when drawer collapses
  onExpandedChanged: {
    if (!expanded) {
      if (root.hostBar && root.hostBar.activePopout && root.isChildItem(root.hostBar.activePopout)) {
        if (typeof root.hostBar.activePopout.close === "function") {
          root.hostBar.activePopout.close()
        }
      }
    }
  }

  IpcHandler {
    target: "nertwork.drawer"

    function toggle(): string {
      root.broadcast("toggleLocal")
      return root.expanded ? "expanded" : "collapsed"
    }

    function expand(): string {
      root.broadcast("expandLocal")
      return "expanded"
    }

    function collapse(): string {
      root.broadcast("collapseLocal")
      return "collapsed"
    }

    function status(): string {
      var repeater = layoutLoader.item ? layoutLoader.item.repeater : null
      var itemsDebug = []
      if (repeater) {
        for (var i = 0; i < repeater.count; i++) {
          var slot = repeater.itemAt(i)
          if (!slot) {
            itemsDebug.push({ index: i, slotNull: true })
            continue
          }
          itemsDebug.push({
            index: i,
            entry: slot.entry,
            moduleName: slot.moduleName,
            registered: slot.registered,
            hasComponent: slot.registryComponent !== null,
            loaderStatus: slot.loaderStatus,
            loaderError: slot.loaderError,
            hasActiveItem: slot.activeItem !== null,
            itemVisible: slot.activeItem ? slot.activeItem.visible : null,
            itemImplicitWidth: slot.activeItem ? slot.activeItem.implicitWidth : null,
            slotImplicitWidth: slot.implicitWidth,
            slotWidth: slot.width,
            slotVisible: slot.visible
          })
        }
      }
      return JSON.stringify({
        expanded: root.expanded,
        contentExtent: root.contentExtent,
        revealExtent: root.revealExtent,
        revealProgress: root.revealProgress,
        implicitWidth: root.implicitWidth,
        width: root.width,
        visible: root.visible,
        hasBar: root.bar !== null,
        hasHostBar: root.hostBar !== null,
        hasRegistry: !!(root.hostBar && root.hostBar.barWidgetRegistry),
        registryWidgetsCount: (root.hostBar && root.hostBar.barWidgetRegistry && root.hostBar.barWidgetRegistry.widgets)
          ? Object.keys(root.hostBar.barWidgetRegistry.widgets).length : 0,
        layoutLoaderItem: layoutLoader.item !== null,
        repeaterCount: repeater ? repeater.count : -1,
        items: itemsDebug
      })
    }
  }

  Loader {
    id: layoutLoader
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalLayout : horizontalLayout
  }

  Component {
    id: horizontalLayout

    Item {
      id: hRoot

      readonly property real contentExtent: {
        var rowWidth = contentRow.implicitWidth
        if (rowWidth > 0) return rowWidth
        var total = 0
        if (childSlotsRepeater) {
          for (var i = 0; i < childSlotsRepeater.count; i++) {
            var slot = childSlotsRepeater.itemAt(i)
            if (slot && slot.implicitWidth > 0) total += slot.implicitWidth
          }
        }
        return total
      }
      readonly property alias repeater: childSlotsRepeater

      implicitWidth: toggleButton.implicitWidth + clipContainer.width
      implicitHeight: root.barSize
      anchors.fill: parent

      BarIconButton {
        id: toggleButton
        bar: root.hostBar
        x: root.chevronOnLeft ? 0 : clipContainer.width
        anchors.verticalCenter: parent.verticalCenter
        text: root.chevronIcon
        tooltipText: root.expanded ? "Collapse drawer" : "Expand drawer"
        onPressed: function(button) {
          if (button === Qt.LeftButton) {
            root.toggleLocal()
          } else if (button === Qt.RightButton) {
            root.broadcast("toggleLocal")
          }
        }
      }

      Item {
        id: clipContainer
        x: root.chevronOnLeft ? toggleButton.implicitWidth : 0
        anchors.verticalCenter: parent.verticalCenter
        width: root.revealExtent
        height: root.barSize
        clip: true
        opacity: root.revealProgress
        enabled: root.revealExtent > 0

        Row {
          id: contentRow
          x: root.chevronOnLeft ? 0 : (root.revealExtent - hRoot.contentExtent)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0

          Repeater {
            id: childSlotsRepeater
            model: root.configuredItems

            DrawerChildSlot {
              required property var modelData
              entry: modelData
            }
          }
        }
      }
    }
  }

  Component {
    id: verticalLayout

    Item {
      id: vRoot

      readonly property real contentExtent: {
        var colHeight = contentCol.implicitHeight
        if (colHeight > 0) return colHeight
        var total = 0
        if (childSlotsRepeater) {
          for (var i = 0; i < childSlotsRepeater.count; i++) {
            var slot = childSlotsRepeater.itemAt(i)
            if (slot && slot.implicitHeight > 0) total += slot.implicitHeight
          }
        }
        return total
      }
      readonly property alias repeater: childSlotsRepeater

      implicitWidth: root.barSize
      implicitHeight: toggleButton.implicitHeight + clipContainer.height
      anchors.fill: parent

      BarIconButton {
        id: toggleButton
        bar: root.hostBar
        y: root.chevronOnLeft ? 0 : clipContainer.height
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.chevronIcon
        textRotation: 90
        tooltipText: root.expanded ? "Collapse drawer" : "Expand drawer"
        onPressed: function(button) {
          if (button === Qt.LeftButton) {
            root.toggleLocal()
          } else if (button === Qt.RightButton) {
            root.broadcast("toggleLocal")
          }
        }
      }

      Item {
        id: clipContainer
        y: root.chevronOnLeft ? toggleButton.implicitHeight : 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.barSize
        height: root.revealExtent
        clip: true
        opacity: root.revealProgress
        enabled: root.revealExtent > 0

        Column {
          id: contentCol
          y: root.chevronOnLeft ? 0 : (root.revealExtent - vRoot.contentExtent)
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 0

          Repeater {
            id: childSlotsRepeater
            model: root.configuredItems

            DrawerChildSlot {
              required property var modelData
              entry: modelData
            }
          }
        }
      }
    }
  }

  component DrawerChildSlot: Item {
    id: slotRoot

    required property var entry
    property string region: "right"
    readonly property real widgetWidth: 0
    readonly property real widgetHeight: 0
    readonly property string moduleName: root.hostBar && typeof root.hostBar.entryId === "function"
      ? root.hostBar.entryId(entry)
      : (typeof entry === "string" ? entry : (entry && entry.id ? entry.id : ""))
    readonly property var moduleSettings: root.hostBar && typeof root.hostBar.entrySettings === "function"
      ? root.hostBar.entrySettings(entry)
      : (typeof entry === "object" ? entry : ({}))
    readonly property var registryComponent: {
      if (!root.hostBar || !root.hostBar.barWidgetRegistry) return null
      var w = root.hostBar.barWidgetRegistry.widgets
      var registryName = Util.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: loader.item
    readonly property int loaderStatus: loader.status
    readonly property string loaderError: loader.status === Loader.Error && typeof loader.errorString === "function" ? loader.errorString() : ""
    readonly property bool panelOpen: root.hostBar && root.hostBar.activePopout === activeItem

    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slotRoot.height : slotRoot.width) * 0.55))
    }

    readonly property real itemExtent: {
      if (!activeItem || activeItem.visible === false) return 0
      var extent = root.vertical ? activeItem.implicitHeight : activeItem.implicitWidth
      if (extent !== undefined && extent !== null && extent > 0) return extent
      return Style.bar.iconSlot
    }

    implicitWidth: root.vertical ? root.barSize : itemExtent
    implicitHeight: root.vertical ? itemExtent : root.barSize
    width: implicitWidth
    height: implicitHeight

    function syncModuleSlot() {
      if (root.hostBar && typeof root.hostBar.registerModuleSlot === "function") {
        root.hostBar.registerModuleSlot(slotRoot)
      }
    }

    Component.onCompleted: syncModuleSlot()
    Component.onDestruction: {
      if (root.hostBar && typeof root.hostBar.unregisterModuleSlot === "function") {
        root.hostBar.unregisterModuleSlot(slotRoot)
      }
    }

    Connections {
      target: root
      function onBarChanged() {
        slotRoot.syncModuleSlot()
        slotRoot.injectProps()
      }
      function onHostBarChanged() {
        slotRoot.syncModuleSlot()
        slotRoot.injectProps()
      }
    }

    Loader {
      id: loader
      anchors.fill: parent
      active: slotRoot.registered
      sourceComponent: slotRoot.registered ? slotRoot.registryComponent : null
      onLoaded: {
        slotRoot.injectProps()
        Qt.callLater(slotRoot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator
      readonly property int inset: Style.space(2)
      visible: opacity > 0
      opacity: slotRoot.panelOpen ? 0.9 : 0
      color: Commons.Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slotRoot.panelIndicatorExtent
      height: root.vertical ? slotRoot.panelIndicatorExtent : Style.space(2)
      x: root.vertical
        ? (root.hostBar && root.hostBar.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.hostBar && root.hostBar.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      if (typeof root === "undefined" || !root) return
      var target = activeItem
      if (!target) return
      if ("fixedEdge" in target && "fixedEdge" in root) target.fixedEdge = root.fixedEdge
      if ("bar" in target) target.bar = root.hostBar
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }
  }
}
