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
// bottom-right corner, and the keyboard itself — a bottom strip that
// reserves its height (exclusive zone) so tiled windows shrink above it
// instead of hiding the focused input behind the keys.
//
// Neither surface ever takes keyboard focus, so the app being typed into
// keeps it. Taps are injected with wtype (part of Omarchy's base package
// set), which means the keyboard types into whatever window has focus,
// exactly like a hardware keyboard would.
//
// Summon/hide from the CLI:  omarchy-shell shell toggle ryan.osk '{}'
// or via the plugin's own target:  omarchy-shell osk toggle
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  property bool opened: false

  // Modifier latches: 0 = off, 1 = one-shot (clears after the next key),
  // 2 = locked (tap the modifier again to release). Caps toggles the shift
  // lock directly, the way caps lock should.
  property int shiftState: 0
  property int ctrlState: 0
  property int altState: 0
  property int superState: 0

  readonly property bool shiftOn: shiftState > 0

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
    Quickshell.execDetached(Model.wtypeArgs(def, {
      shift: shiftState > 0,
      ctrl: ctrlState > 0,
      alt: altState > 0,
      super: superState > 0
    }))
    releaseOneShots()
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
    if (altState === 1) altState = 0
    if (superState === 1) superState = 0
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

  // ---- the keyboard -------------------------------------------------------
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { bottom: true; left: true; right: true }
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.namespace: "omarchy-osk"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Auto
    // Only the card itself takes input; clicks beside it on wide screens
    // fall through to whatever is below.
    mask: Region { item: card }

    readonly property real gap: Style.space(6)
    readonly property real pad: Style.space(10)
    readonly property real cardWidth: Math.min(panel.width - Style.gapsOut * 2, Style.space(960))
    // Every row spans 16 units with 15 gaps between keys, whatever the key
    // count, so one unit size lines the whole grid up.
    readonly property real unit: (cardWidth - card.borderLeft - card.borderRight - pad * 2 - gap * 15) / 16
    readonly property real keyHeight: Math.round(unit * 0.85)

    BorderSurface {
      id: card
      width: panel.cardWidth
      height: card.borderTop + card.borderBottom + panel.pad * 2
        + panel.keyHeight * 5 + panel.gap * 4
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
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
