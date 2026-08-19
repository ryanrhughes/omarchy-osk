import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "KeyboardModel.js" as Model

// A touch-friendly on-screen keyboard.
//
// Two layer-shell surfaces: a persistent toggle button pinned to the
// bottom-right corner, and the keyboard itself. The keyboard has two modes:
//
//   docked   — a bottom strip that reserves its height (exclusive zone) so
//              tiled windows shrink above it instead of hiding the focused
//              input behind the keys.
//   floating — reserves nothing and sits above windows; drag it anywhere
//              by the handle strip along its top edge.
//
// The handle strip also carries the mode toggle and an explicit close
// button. Dragging the handle while docked tears the keyboard off into
// floating mode. Mode and float position persist across sessions in
// ~/.local/state/omarchy/<plugin-id>.json.
//
// Neither surface ever takes keyboard focus, so the app being typed into
// keeps it. Taps are injected with wtype (part of Omarchy's base package
// set), which means the keyboard types into whatever window has focus,
// exactly like a hardware keyboard would.
//
// Summon/hide from the CLI:  omarchy-shell shell toggle <plugin-id> '{}'
// or via the plugin's own target:  omarchy-shell osk toggle
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  property bool opened: false

  // Docked pushes tiles; floating overlays them at (floatX, floatY),
  // measured as left/bottom margins. -1 means "never floated yet" and
  // picks a sensible spot on first undock.
  property bool docked: true
  property real floatX: -1
  property real floatY: -1

  // Modifier latches: 0 = off, 1 = one-shot (clears after the next key),
  // 2 = locked (tap the modifier again to release). Caps toggles the shift
  // lock directly, the way caps lock should.
  property int shiftState: 0
  property int ctrlState: 0
  property int altState: 0
  property int superState: 0

  readonly property bool shiftOn: shiftState > 0

  readonly property string stateDir: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/omarchy"
  }
  // Computed on demand rather than bound: the host injects `manifest` after
  // instantiation, and a stale binding read here once sent the state load to
  // the fallback filename.
  function statePath() {
    return stateDir + "/" + (manifest ? manifest.id : "osk") + ".json"
  }

  function open(payloadJson) { opened = true }

  function close() {
    opened = false
    stopRepeat()
    shiftState = 0
    ctrlState = 0
    altState = 0
    superState = 0
  }

  // Route open/close through the shell where possible so its
  // summoned-panel bookkeeping stays in sync with what is on screen.
  function toggleRequested() {
    if (shell && manifest) shell.toggle(manifest.id, "{}")
    else if (opened) close()
    else open("{}")
  }

  function dismiss() {
    if (shell && manifest) shell.hide(manifest.id)
    else close()
  }

  // Deliberate mode change (button, IPC): reposition the card for the new
  // mode. Tear-off during a drag skips this — the drag is already moving
  // the card and a layout snap would yank it out from under the pointer.
  function setDocked(value) {
    if (!value && floatX < 0) {
      // First undock: lift off from where the docked keyboard sits.
      floatX = Math.round((panel.width - panel.cardWidth) / 2)
      floatY = Style.gapsOut
    }
    docked = value
    layoutCard()
    saveState()
  }

  function tearOff() {
    if (!docked) return
    docked = false
    // The card keeps its dragged position; it becomes the float position
    // when the gesture releases.
  }

  // The card's x/y are plain properties (MouseArea.drag writes them
  // directly), so every non-drag position change goes through here.
  function layoutCard() {
    if (dragArea.drag.active) return
    if (docked) {
      card.x = Math.round((panel.width - card.width) / 2)
      card.y = panel.height - card.height
      return
    }
    if (floatX >= 0) {
      floatX = Math.min(Math.max(0, floatX), Math.max(0, panel.width - card.width))
      floatY = Math.min(Math.max(0, floatY), Math.max(0, panel.height - card.height))
    }
    card.x = Math.round(Math.max(0, floatX))
    card.y = panel.height - card.height - Math.round(Math.max(0, floatY))
  }

  function saveState() {
    var json = JSON.stringify({ docked: docked, floatX: Math.round(floatX), floatY: Math.round(floatY) })
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p \"$0\" && printf '%s' \"$1\" > \"$2\"", stateDir, json, statePath()])
  }

  function applyState(text) {
    try {
      var data = JSON.parse(text)
      if (typeof data.docked === "boolean") docked = data.docked
      if (isFinite(Number(data.floatX)) && Number(data.floatX) >= 0) floatX = Number(data.floatX)
      if (isFinite(Number(data.floatY)) && Number(data.floatY) >= 0) floatY = Number(data.floatY)
    } catch (e) { /* first run or unreadable */ }
    layoutCard()
  }

  // The host injects `manifest` after instantiation, so wait for it before
  // reading the state file — statePath is derived from the plugin id.
  property bool stateLoadStarted: false

  function loadStateOnce() {
    if (stateLoadStarted || !manifest) return
    stateLoadStarted = true
    stateLoadProcess.command = ["bash", "-c", "cat \"$0\" 2>/dev/null || true", statePath()]
    stateLoadProcess.running = true
  }

  onManifestChanged: loadStateOnce()
  Component.onCompleted: loadStateOnce()

  Process {
    id: stateLoadProcess
    stdout: StdioCollector {
      id: stateLoadOutput
      waitForEnd: true
    }
    onExited: root.applyState(stateLoadOutput.text)
  }

  function tap(def) {
    if (def.kind === "mod") {
      cycleMod(def.mod)
      return
    }
    if (def.kind === "hide") {
      dismiss()
      return
    }
    commit(def)
  }

  function commit(def) {
    // Super chords can't be delivered: the compositor's bind matching
    // resolves virtual-keyboard keycodes against the hardware keymap, so a
    // Super chord sent through wtype fires whatever global bind sits at
    // wtype's synthetic keycode (SUPER+ESCAPE, in practice). Firing random
    // shortcuts is worse than firing none, so drop the chord and say why.
    if (superState > 0) {
      superState = 0
      releaseOneShots()
      Quickshell.execDetached(["omarchy-notification-send",
        "On-Screen Keyboard",
        "Super shortcuts can't be sent from the on-screen keyboard yet"])
      return
    }
    enqueueSend(Model.wtypeArgs(def, {
      shift: shiftState > 0,
      ctrl: ctrlState > 0,
      alt: altState > 0,
      super: false
    }))
    releaseOneShots()
  }

  // ---- key send queue -----------------------------------------------------
  // wtype invocations must not overlap: each one creates its own virtual
  // keyboard with its own keymap, and two alive at once make the compositor
  // interleave keymap switches — keys get dropped (observed under
  // auto-repeat). One process at a time, strictly in tap order.
  property var sendQueue: []
  property bool sending: false

  function enqueueSend(args) {
    var queue = sendQueue.slice()
    queue.push(args)
    sendQueue = queue
    pumpSendQueue()
  }

  function pumpSendQueue() {
    if (sending || sendQueue.length === 0) return
    sending = true
    var next = sendQueue[0]
    sendQueue = sendQueue.slice(1)
    sendProcess.command = next
    sendProcess.running = true
  }

  Process {
    id: sendProcess
    onExited: {
      root.sending = false
      root.pumpSendQueue()
    }
  }

  function cycleMod(mod) {
    if (mod === "shift") shiftState = (shiftState + 1) % 3
    else if (mod === "caps") shiftState = shiftState === 2 ? 0 : 2
    else if (mod === "ctrl") ctrlState = (ctrlState + 1) % 3
    else if (mod === "alt") altState = (altState + 1) % 3
    else if (mod === "super") superState = (superState + 1) % 3
  }

  function releaseOneShots() {
    if (shiftState === 1) shiftState = 0
    if (ctrlState === 1) ctrlState = 0
    if (superState === 1) superState = 0
    if (altState === 1) altState = 0
  }

  function modState(mod) {
    if (mod === "shift") return shiftState
    if (mod === "caps") return shiftState === 2 ? 2 : 0
    if (mod === "ctrl") return ctrlState
    if (mod === "alt") return altState
    if (mod === "super") return superState
    return 0
  }

  // ---- key auto-repeat ----------------------------------------------------
  // One shared driver rather than timers per key. Timers are started
  // imperatively; `running:` bindings on Timer are unreliable in this
  // quickshell build.
  property var repeatDef: null

  function startRepeat(def) {
    repeatDef = def
    repeatDelay.restart()
  }

  function stopRepeat() {
    repeatDef = null
    repeatDelay.stop()
    repeatTick.stop()
  }

  Timer {
    id: repeatDelay
    interval: 420
    onTriggered: repeatTick.start()
  }

  Timer {
    id: repeatTick
    interval: 55
    repeat: true
    onTriggered: if (root.repeatDef) root.commit(root.repeatDef)
  }

  IpcHandler {
    target: "osk"
    function toggle(): string { root.toggleRequested(); return "ok" }
    function close(): string { root.dismiss(); return "ok" }
    function press(name: string): string {
      var def = Model.findKey(name)
      if (!def) return "unknown key: " + name
      root.tap(def)
      return "ok"
    }
    function dock(): string { root.setDocked(true); return "ok" }
    function undock(): string { root.setDocked(false); return "ok" }
    function mode(): string { return root.docked ? "docked" : "floating" }
    function moveTo(x: string, y: string): string {
      root.floatX = Number(x)
      root.floatY = Number(y)
      root.setDocked(false)
      return "ok"
    }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // ---- persistent toggle button ------------------------------------------
  PanelWindow {
    id: buttonWindow
    visible: !root.opened
    anchors { bottom: true; right: true }
    margins { bottom: Style.gapsOut; right: Style.gapsOut }
    implicitWidth: Math.round(Style.space(46))
    implicitHeight: Math.round(Style.space(46))
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osk-toggle"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Reserve nothing, but respect other zones so the button rides above a
    // bottom-positioned bar instead of overlapping it.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    BorderSurface {
      id: buttonCard
      anchors.fill: parent
      color: Util.alpha(Color.background, buttonArea.containsMouse ? 1.0 : 0.92)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Text {
        anchors.centerIn: parent
        text: Model.GLYPH.keyboard
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
        color: buttonArea.containsMouse ? Color.accent : Color.popups.text
      }

      MouseArea {
        id: buttonArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleRequested()
      }
    }
  }

  // Docked mode's only job besides position is reserving space. That is
  // delegated to this invisible bottom strip so the keyboard window itself
  // never changes geometry — not on mode switches, not mid-drag. A window
  // that resizes or moves during a drag lags the compositor round-trip
  // behind the pointer and the drag runs away (spirals, flies off).
  PanelWindow {
    id: reserveWindow
    visible: root.opened && root.docked
    anchors { bottom: true; left: true; right: true }
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osk-reserve"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Auto
    // Reservation only; all input passes through.
    mask: Region {}
  }

  // ---- the keyboard -------------------------------------------------------
  PanelWindow {
    id: panel
    visible: root.opened
    // Always a full-screen transparent overlay; the card is positioned as
    // an item inside it (bottom-center when docked, floatX/floatY when
    // floating). Item movement is synchronous with the pointer, which is
    // what keeps drags pinned under the finger.
    anchors { bottom: true; left: true; right: true; top: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osk"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Only the card itself takes input; clicks anywhere else fall through
    // to whatever is below.
    mask: Region { item: card }

    onWidthChanged: root.layoutCard()
    onHeightChanged: root.layoutCard()
    onVisibleChanged: if (visible) root.layoutCard()

    readonly property real screenWidth: panel.screen ? panel.screen.width : 1920
    readonly property real screenHeight: panel.screen ? panel.screen.height : 1080
    readonly property real gap: Style.space(6)
    readonly property real pad: Style.space(10)
    readonly property real handleHeight: Style.space(22)
    readonly property real cardWidth: Math.min(screenWidth - Style.gapsOut * 2, Style.space(960))
    // Every row spans 16 units with 15 gaps between keys, whatever the key
    // count, so one unit size lines the whole grid up.
    readonly property real unit: (cardWidth - card.borderLeft - card.borderRight - pad * 2 - gap * 15) / 16
    readonly property real keyHeight: Math.round(unit * 0.85)

    BorderSurface {
      id: card
      width: panel.cardWidth
      height: card.borderTop + card.borderBottom + panel.pad * 2
        + panel.handleHeight + panel.keyHeight * 5 + panel.gap * 5
      // x/y are set by layoutCard() and by MouseArea.drag — deliberately
      // not bindings, so the drag can own them during a gesture.
      onWidthChanged: root.layoutCard()
      onHeightChanged: root.layoutCard()
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.borderTop + panel.pad
        anchors.bottomMargin: card.borderBottom + panel.pad
        anchors.leftMargin: card.borderLeft + panel.pad
        anchors.rightMargin: card.borderRight + panel.pad
        spacing: panel.gap

        // Handle strip: drag pill in the middle, mode toggle + close on the
        // right. Dragging it moves a floating keyboard; dragging while
        // docked tears the keyboard off into floating mode.
        Item {
          id: handle
          width: parent.width
          height: panel.handleHeight

          MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.docked ? Qt.OpenHandCursor : Qt.SizeAllCursor
            // Qt's own drag machinery moves the card; hand-rolled pointer
            // math here has twice produced runaway drags (async window
            // moves, then stale item-local coordinates re-projected through
            // a moved transform).
            drag.target: card
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 0
            drag.maximumX: Math.max(0, card.parent ? card.parent.width - card.width : 0)
            drag.minimumY: 0
            drag.maximumY: Math.max(0, card.parent ? card.parent.height - card.height : 0)
            drag.onActiveChanged: {
              // A drag beginning while docked tears the keyboard off; the
              // gesture keeps moving it as a floating card.
              if (drag.active && root.docked) root.tearOff()
            }
            onReleased: {
              if (root.docked) return
              root.floatX = card.x
              root.floatY = card.parent.height - card.y - card.height
              root.saveState()
            }
          }

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(52)
            height: Style.space(4)
            radius: height / 2
            color: Util.alpha(Color.popups.text, dragArea.containsMouse ? 0.5 : 0.28)
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            HandleButton {
              face: root.docked ? Model.GLYPH.floatOut : Model.GLYPH.dock
              hoverColor: Color.accent
              onTapped: root.setDocked(!root.docked)
            }

            HandleButton {
              face: Model.GLYPH.close
              hoverColor: Color.urgent
              onTapped: root.dismiss()
            }
          }
        }

        Repeater {
          model: Model.ROWS

          Row {
            required property var modelData
            spacing: panel.gap

            Repeater {
              model: modelData

              Key {
                required property var modelData
                def: modelData
              }
            }
          }
        }
      }
    }
  }

  component HandleButton: Rectangle {
    id: handleButton

    property string face: ""
    property color hoverColor: Color.accent
    signal tapped()

    width: panel.handleHeight
    height: panel.handleHeight
    radius: Math.min(Style.cornerRadius, Style.space(6))
    color: handleButtonArea.containsMouse
      ? Util.alpha(handleButton.hoverColor, 0.25)
      : "transparent"

    Text {
      anchors.centerIn: parent
      text: handleButton.face
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      color: handleButtonArea.containsMouse ? handleButton.hoverColor : Color.popups.text
    }

    MouseArea {
      id: handleButtonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: handleButton.tapped()
    }
  }

  component Key: Rectangle {
    id: key

    property var def

    readonly property int latch: def.kind === "mod" ? root.modState(def.mod) : 0
    readonly property bool isChar: def.kind === "char"
    readonly property string face: isChar
      ? (root.shiftOn ? def.shift : def.base)
      : (def.label || "")
    // Word labels (Enter, Shift, ...) render small; single-glyph faces
    // (characters, arrows, the hide glyph) render at key size. Counted in
    // codepoints — nerd glyphs are two UTF-16 units but one face.
    readonly property bool wordLabel: !isChar && Array.from(face).length > 1

    width: panel.unit * def.span + panel.gap * (def.span - 1)
    height: panel.keyHeight
    radius: Math.min(Style.cornerRadius, Style.space(10))
    color: keyArea.pressed
      ? Util.alpha(Color.accent, 0.45)
      : latch === 2
        ? Util.alpha(Color.accent, 0.5)
        : latch === 1
          ? Util.alpha(Color.accent, 0.3)
          : Util.alpha(Color.foreground, keyArea.containsMouse ? 0.14 : 0.07)
    border.width: latch === 2 ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent

    Text {
      anchors.centerIn: parent
      text: key.face
      font.family: Style.font.family
      font.pixelSize: key.wordLabel ? Style.font.bodySmall : Style.font.title
      color: Color.popups.text
    }

    MouseArea {
      id: keyArea
      anchors.fill: parent
      hoverEnabled: true
      onPressed: {
        root.tap(key.def)
        if (key.def.repeat) root.startRepeat(key.def)
      }
      onReleased: root.stopRepeat()
      onCanceled: root.stopRepeat()
    }
  }
}
