// Layout and wtype argument construction for the on-screen keyboard.
//
// Key kinds:
//   char — produces a character. `base`/`shift` are the two printed faces;
//          `keysym` names the underlying XKB key so modifier chords
//          (ctrl+c, super+t) can be sent as key events instead of text.
//   key  — a named XKB keysym with no character face (Return, arrows, ...).
//   mod  — a latching modifier; `mod` is which one.
//   hide — dismisses the keyboard.
//
// Every row spans exactly 16 units so the grid stays a clean rectangle.

// Glyphs are built from codepoints rather than pasted literally so file
// editing tools can never mangle them (see agents/skills/shell-dev.md).
var GLYPH = {
  keyboard: String.fromCodePoint(0xf030c), // nf-md-keyboard
  hide: String.fromCodePoint(0xf0310),     // nf-md-keyboard_off
  close: String.fromCodePoint(0xf0156),    // nf-md-close
  floatOut: String.fromCodePoint(0xf05b2), // nf-md-window_restore
  dock: String.fromCodePoint(0xf10a9),     // nf-md-dock_bottom
  left: String.fromCodePoint(0x2190),
  up: String.fromCodePoint(0x2191),
  right: String.fromCodePoint(0x2192),
  down: String.fromCodePoint(0x2193)
}

function charKey(base, shift, keysym, span) {
  return { kind: "char", base: base, shift: shift, keysym: keysym, span: span || 1, repeat: true }
}

function specialKey(label, keysym, span, repeat) {
  return { kind: "key", label: label, keysym: keysym, span: span, repeat: repeat === true }
}

function modKey(label, mod, span) {
  return { kind: "mod", label: label, mod: mod, span: span }
}

var ROWS = [
  [
    specialKey("Esc", "Escape", 1, false),
    charKey("`", "~", "grave"),
    charKey("1", "!", "1"),
    charKey("2", "@", "2"),
    charKey("3", "#", "3"),
    charKey("4", "$", "4"),
    charKey("5", "%", "5"),
    charKey("6", "^", "6"),
    charKey("7", "&", "7"),
    charKey("8", "*", "8"),
    charKey("9", "(", "9"),
    charKey("0", ")", "0"),
    charKey("-", "_", "minus"),
    charKey("=", "+", "equal"),
    specialKey("Backspace", "BackSpace", 2, true)
  ],
  [
    specialKey("Tab", "Tab", 1.5, false),
    charKey("q", "Q", "q"),
    charKey("w", "W", "w"),
    charKey("e", "E", "e"),
    charKey("r", "R", "r"),
    charKey("t", "T", "t"),
    charKey("y", "Y", "y"),
    charKey("u", "U", "u"),
    charKey("i", "I", "i"),
    charKey("o", "O", "o"),
    charKey("p", "P", "p"),
    charKey("[", "{", "bracketleft"),
    charKey("]", "}", "bracketright"),
    charKey("\\", "|", "backslash", 1.5),
    specialKey("Del", "Delete", 1, true)
  ],
  [
    modKey("Caps", "caps", 1.75),
    charKey("a", "A", "a"),
    charKey("s", "S", "s"),
    charKey("d", "D", "d"),
    charKey("f", "F", "f"),
    charKey("g", "G", "g"),
    charKey("h", "H", "h"),
    charKey("j", "J", "j"),
    charKey("k", "K", "k"),
    charKey("l", "L", "l"),
    charKey(";", ":", "semicolon"),
    charKey("'", "\"", "apostrophe"),
    specialKey("Enter", "Return", 3.25, false)
  ],
  [
    modKey("Shift", "shift", 2.25),
    charKey("z", "Z", "z"),
    charKey("x", "X", "x"),
    charKey("c", "C", "c"),
    charKey("v", "V", "v"),
    charKey("b", "B", "b"),
    charKey("n", "N", "n"),
    charKey("m", "M", "m"),
    charKey(",", "<", "comma"),
    charKey(".", ">", "period"),
    charKey("/", "?", "slash"),
    modKey("Shift", "shift", 1.75),
    specialKey(GLYPH.up, "Up", 1, true),
    { kind: "hide", label: GLYPH.hide, span: 1 }
  ],
  [
    modKey("Ctrl", "ctrl", 1.25),
    modKey("Super", "super", 1.25),
    modKey("Alt", "alt", 1.25),
    specialKey("", "space", 8.25, true),
    modKey("Ctrl", "ctrl", 1),
    specialKey(GLYPH.left, "Left", 1, true),
    specialKey(GLYPH.down, "Down", 1, true),
    specialKey(GLYPH.right, "Right", 1, true)
  ]
]

// Find a key by what a caller would naturally name it: the unshifted face
// for characters ("a", "/"), the keysym for specials ("Return", "space"),
// or the printed label ("Shift", "Backspace"). Used by the plugin's IPC
// `press` method so taps can be scripted and tested from the CLI.
function findKey(name) {
  for (var r = 0; r < ROWS.length; r++) {
    for (var c = 0; c < ROWS[r].length; c++) {
      var def = ROWS[r][c]
      if (def.kind === "char" && def.base === name) return def
      if (def.keysym === name) return def
      if (def.label === name) return def
    }
  }
  return null
}

// wtype invocation for one key tap under the current latches.
// mods: { shift, ctrl, alt, super } booleans.
//
// Plain characters go through wtype's text mode, which picks the right
// keysym (and shift level) for the exact character — including the shifted
// faces. The one exception is a bare "-", which text mode would parse as an
// option, so unshifted characters use `-k <keysym>` instead. Modifier chords
// must be key events: hold the modifiers with -M, tap the keysym, release
// with -m (the pattern omarchy-clipboard-paste-text already relies on).
function wtypeArgs(k, mods) {
  var held = []
  if (mods.ctrl) held.push("ctrl")
  if (mods.alt) held.push("alt")
  if (mods.super) held.push("logo")

  if (k.kind === "char" && held.length === 0) {
    if (mods.shift) return ["wtype", k.shift]
    return ["wtype", "-k", k.keysym]
  }

  if (mods.shift) held.unshift("shift")
  var args = ["wtype"]
  for (var i = 0; i < held.length; i++) args.push("-M", held[i])
  args.push("-k", k.keysym)
  for (var j = held.length - 1; j >= 0; j--) args.push("-m", held[j])
  return args
}
