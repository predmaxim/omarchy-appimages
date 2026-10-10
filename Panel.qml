import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

// AppImages in ~/AppImages: into the app menu and out of it, delete, update
// from GitHub releases. A modal in the middle of the screen, summoned from the
// Omarchy menu (Install › AppImage): omarchy-shell shell toggle predmaxim.appimages.
// The file work is appimages.sh; which release file is newer is Model.js.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: (root.manifest && root.manifest.id) || "predmaxim.appimages"
  readonly property string script: String(Qt.resolvedUrl("appimages.sh")).replace(/^file:\/\//, "")
  readonly property string folder: Quickshell.env("HOME") + "/AppImages"
  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))
  readonly property color fg: Color.popups.text
  readonly property color muted: Color.muted
  readonly property string fontFamily: Style.font.family

  property var apps: []
  // file -> { version, url } after a check; file -> true when its check failed.
  property var updates: ({})
  property var failed: ({})
  property var repos: ({})
  property bool checking: false
  property var checkQueue: []
  // The file an add/remove/update/delete is running for.
  property string busyFile: ""
  property string notice: ""
  // Page: "list" or "repos" (settings, behind the gear).
  property string page: "list"
  // Row under the keyboard/mouse cursor; -2: the header, where headCol picks the button.
  property int cursor: -1
  property int headCol: 0
  property string pendingDelete: ""
  property bool fieldFocused: false

  readonly property int registeredCount: apps.filter(function(a) { return a.registered }).length
  readonly property int updateCount: Object.keys(updates).length
  readonly property int headButtons: page === "list" ? 3 : 1

  function open(payloadJson) {
    root.opened = true
    root.refresh()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.page = "list"
    root.cursor = -1
    root.notice = ""
    confirm.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // Esc step by step: dialog, settings page, then close.
  function back() {
    if (confirm.opened) { confirm.opened = false; return }
    if (root.page !== "list") { root.showPage("list"); return }
    root.dismiss()
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function run(file, args) {
    if (root.busyFile) return
    root.busyFile = file
    root.notice = ""
    actProc.command = [root.script].concat(args)
    actProc.running = true
  }

  function toggleMenu(app) {
    if (app) root.run(app.file, [app.registered ? "unregister" : "add", app.path])
  }

  function updateApp(app) {
    var update = app && root.updates[app.file]
    if (update) root.run(app.file, ["update", app.path, update.url])
  }

  function askDelete(app) {
    if (!app || root.busyFile) return
    root.pendingDelete = app.file
    confirm.selectedIndex = 0   // never preselect the destructive button
    confirm.opened = true
  }

  function deleteApp() {
    var app = root.apps.filter(function(a) { return a.file === root.pendingDelete })[0]
    if (app) root.run(app.file, ["delete", app.path])
  }

  function check() {
    if (root.checking) return
    var queue = root.apps.filter(function(a) { return Model.sourceFor(a, root.repos) !== null })
    root.updates = {}
    root.failed = {}
    if (!queue.length) { root.notice = root.tr("No update sources: see settings"); return }
    root.notice = ""
    root.checking = true
    root.checkQueue = queue
    root.checkNext()
  }

  function checkNext() {
    if (!root.checkQueue.length) {
      root.checking = false
      if (!root.updateCount) root.notice = root.tr("No updates")
      return
    }
    var app = root.checkQueue[0]
    var source = Model.sourceFor(app, root.repos)
    relProc.app = app
    relProc.glob = source.glob
    relProc.command = [root.script, "release", source.repo, source.tag]
    relProc.running = true
  }

  function checked(app, glob, text) {
    var release = null
    try { release = JSON.parse(text) } catch (e) {}
    if (release) {
      var update = Model.updateFor(app, release, glob)
      if (update) {
        var next = Object.assign({}, root.updates)
        next[app.file] = update
        root.updates = next
      }
    } else {
      var bad = Object.assign({}, root.failed)
      bad[app.file] = true
      root.failed = bad
    }
    root.checkQueue = root.checkQueue.slice(1)
    root.checkNext()
  }

  function saveRepo(file, text) {
    var next = Model.withRepo(root.repos, file, text)
    if (JSON.stringify(next) === JSON.stringify(root.repos)) return
    root.repos = next
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, { repos: next })
  }

  function openFolder() {
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && exec xdg-open "$1"', "sh", root.folder])
  }

  function showPage(page) {
    root.page = page
    root.notice = ""
    root.cursor = -2
    root.headCol = 0
    keyCatcher.forceActiveFocus()
  }

  function moveCursor(dy) {
    var count = root.page === "list" ? root.apps.length : 0
    if (dy < 0 && root.cursor <= 0) { root.cursor = -2; return }
    if (count === 0) { root.cursor = -2; return }
    root.cursor = Math.max(0, Math.min(count - 1, root.cursor < 0 ? 0 : root.cursor + dy))
    list.positionViewAtIndex(root.cursor, ListView.Contain)
  }

  // Enter on the header: check, folder, gear (list page); Back (settings page).
  function activateHeader() {
    if (root.page !== "list") root.showPage("list")
    else if (root.headCol === 0) root.check()
    else if (root.headCol === 1) root.openFolder()
    else root.showPage("repos")
  }

  function cursorApp() {
    return root.page === "list" && root.cursor >= 0 ? root.apps[root.cursor] : null
  }

  onAppsChanged: if (root.cursor >= root.apps.length) root.cursor = root.apps.length - 1

  Process {
    id: listProc
    command: [root.script, "list"]
    stdout: StdioCollector { id: listed }
    stderr: StdioCollector { id: listErrors }
    onExited: function(code) {
      var parsed = null
      try { parsed = JSON.parse(listed.text) } catch (e) {}
      if (code === 0 && Array.isArray(parsed)) root.apps = parsed
      else root.notice = root.tr("Failed: %1", listErrors.text.trim())
    }
  }

  Process {
    id: actProc
    stderr: StdioCollector { id: actErrors }
    onExited: function(code) {
      if (code !== 0) root.notice = root.tr("Failed: %1", actErrors.text.trim())
      else if (command[1] === "update" || command[1] === "delete") {
        var next = Object.assign({}, root.updates)
        delete next[root.busyFile]
        root.updates = next
      }
      root.busyFile = ""
      root.refresh()
    }
  }

  Process {
    id: relProc
    property var app: null
    property string glob: ""
    stdout: StdioCollector { id: released }
    onExited: function(code) { root.checked(relProc.app, relProc.glob, code === 0 ? released.text : "") }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.repos = Model.readRepos(text(), root.pluginId)
  }

  PanelWindow {
    id: modal
    visible: root.opened
    color: Color.menu.scrim
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "predmaxim-appimages"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(560), modal.width - Style.space(80))
      height: Math.min(column.implicitHeight + card.contentTopInset + card.contentBottomInset, modal.height * 0.85)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent }   // clicks on the card stay on it

    // What the catcher lets through: the dialog's keys and Delete.
    Item {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      Keys.onPressed: function(event) {
        if (confirm.opened) { if (confirm.handleKey(event)) event.accepted = true; return }
        if (event.key === Qt.Key_Delete && !root.fieldFocused) { root.askDelete(root.cursorApp()); event.accepted = true }
      }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: confirm.opened || root.fieldFocused
      onMoveRequested: function(dx, dy) {
        if (dx) { if (root.cursor === -2) root.headCol = Math.max(0, Math.min(root.headButtons - 1, root.headCol + dx)) }
        else if (root.page === "repos" && dy > 0 && repoFields.count) repoFields.itemAt(0).field.forceActiveFocus()
        else root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursor === -2) root.activateHeader(); else root.toggleMenu(root.cursorApp())
      onDeleteRequested: root.askDelete(root.cursorApp())
      onCloseRequested: root.back()
      onTextKey: function(text) { if (text === "u" || text === "U") root.updateApp(root.cursorApp()) }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        message: root.tr("Delete %1?", root.pendingDelete)
        cancelText: root.tr("Cancel")
        confirmText: root.tr("Delete")
        selectedIndex: 0
        fontFamily: root.fontFamily
        onConfirmed: { opened = false; root.deleteApp() }
        onCanceled: opened = false
      }

      PointerMoveGate { id: pointerGate; referenceItem: column }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          title: root.tr("AppImages")
          meta: root.notice
            || (root.checking ? root.tr("Checking for updates…")
            : root.updateCount ? root.tr("Updates: %1", root.updateCount)
            : root.tr("In the menu: %1 of %2", root.registeredCount, root.apps.length))
          foreground: root.fg
          fontFamily: root.fontFamily
          iconComponent: Text {
            text: "󰀻"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
          trailingControl: Row {
            spacing: Style.space(10)
            Repeater {
              model: root.page === "list"
                ? [{ icon: "󰚰", tip: root.tr("Check for updates") }, { icon: "󰉋", tip: root.tr("Open folder") }, { icon: "󰒓", tip: root.tr("Settings") }]
                : [{ icon: "󰁍", tip: root.tr("Back") }]
              Button {
                required property var modelData
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                iconText: modelData.icon
                iconSpinning: root.page === "list" && index === 0 && root.checking
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
                height: width
                tooltipText: modelData.tip
                foreground: root.fg
                fontFamily: root.fontFamily
                hasCursor: root.cursor === -2 && root.headCol === index
                onClicked: { root.cursor = -2; root.headCol = index; root.activateHeader() }
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Text {
          visible: root.page === "list" && !root.apps.length
          width: parent.width
          wrapMode: Text.Wrap
          text: root.tr("No AppImages yet: put files into ~/AppImages.")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        ListView {
          id: list
          visible: root.page === "list"
          width: parent.width
          height: Math.min(contentHeight, modal.height * 0.6)
          clip: true
          spacing: Style.spacing.xs
          boundsBehavior: Flickable.StopAtBounds
          model: root.apps

          delegate: CursorSurface {
            id: row
            required property var modelData
            required property int index
            readonly property var update: root.updates[modelData.file]
            readonly property bool busy: root.busyFile === modelData.file
            width: list.width
            implicitHeight: Math.max(Style.space(50), texts.implicitHeight + Style.spacing.rowPaddingX * 2)
            foreground: root.fg
            hasCursor: root.cursor === index

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              onPositionChanged: function(mouse) { if (pointerGate.moved(rowMouse, mouse)) root.cursor = row.index }
            }

            Image {
              id: icon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.iconLarge * 1.6
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              // A new version of the file keeps the cache path: mtime busts the image cache.
              source: row.modelData.icon ? "file://" + row.modelData.icon + "?" + row.modelData.mtime : ""
              cache: false
            }
            Text {
              visible: !row.modelData.icon
              anchors.centerIn: icon
              text: "󰀻"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
            }

            Column {
              id: texts
              anchors.left: icon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: actions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: row.modelData.name || row.modelData.file
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: Model.statusLine(row.modelData, row.update, root.failed[row.modelData.file] === true, root.tr)
                color: row.update ? Color.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Row {
              id: actions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Button {
                visible: !!row.update
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰚰"
                iconSpinning: row.busy
                text: root.tr("Update")
                bordered: true
                fontSize: Style.font.title
                iconSize: Style.font.title
                foreground: root.fg
                fontFamily: root.fontFamily
                enabled: !root.busyFile
                onClicked: root.updateApp(row.modelData)
              }
              Button {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰆴"
                iconSize: Style.font.title
                tooltipText: root.tr("Delete")
                foreground: root.fg
                fontFamily: root.fontFamily
                enabled: !root.busyFile
                onClicked: root.askDelete(row.modelData)
              }
              ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: row.modelData.registered
                busy: row.busy
                enabled: !root.busyFile
                foreground: root.fg
                onToggled: { root.cursor = row.index; root.toggleMenu(row.modelData) }
                PanelToolTip { visible: parent.containsMouse; text: row.modelData.registered ? root.tr("Remove from the menu") : root.tr("Add to the menu") }
              }
            }
          }
        }

        // Settings: a GitHub repository per AppImage, for updates.
        Column {
          visible: root.page === "repos"
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: root.tr("GITHUB REPOSITORY · OWNER/REPO OR LINK")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            font.letterSpacing: 1.2
          }

          Repeater {
            id: repoFields
            model: root.page === "repos" ? root.apps : []
            delegate: Row {
              id: repoRow
              required property var modelData
              required property int index
              property alias field: field
              readonly property var builtIn: Model.parseUpdateInfo(modelData.update)
              width: parent.width
              spacing: Style.space(12)

              Text {
                id: label
                width: parent.width * 0.4
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: repoRow.modelData.name || repoRow.modelData.file
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
              TextField {
                id: field
                width: parent.width - label.width - parent.spacing
                text: root.repos[repoRow.modelData.file] || ""
                placeholderText: repoRow.builtIn ? root.tr("Built in: %1", repoRow.builtIn.repo) : "owner/repo"
                foreground: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                onActiveFocusChanged: {
                  root.fieldFocused = activeFocus
                  if (!activeFocus) root.saveRepo(repoRow.modelData.file, text)
                }
                onAccepted: root.saveRepo(repoRow.modelData.file, text)
                // ↑/↓ walk the fields; ↑ from the first goes to Back, Esc back to the list.
                Keys.onUpPressed: {
                  if (repoRow.index > 0) repoFields.itemAt(repoRow.index - 1).field.forceActiveFocus()
                  else { root.cursor = -2; root.headCol = 0; keyCatcher.forceActiveFocus() }
                }
                Keys.onDownPressed: if (repoRow.index < repoFields.count - 1) repoFields.itemAt(repoRow.index + 1).field.forceActiveFocus()
                Keys.onEscapePressed: root.showPage("list")
              }
            }
          }
        }
      }
    }
    }
    }
  }
}
