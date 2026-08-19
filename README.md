# On-Screen Keyboard for Omarchy

A touch-friendly on-screen keyboard for tablets and touchscreen machines, built as an [Omarchy](https://omarchy.org) shell plugin.

A small keyboard button sits in the bottom-right corner of the screen at all times. Tap it and a full QWERTY keyboard rises from the bottom edge, reserving its space so tiled windows shrink above it — the focused input never hides behind the keys. Tap the keyboard-off key (bottom-right of the board) to put it away and get the button back.

Keys are injected with `wtype` (part of Omarchy's base package set), so the keyboard types into whichever window has focus, exactly like a hardware keyboard. The keyboard itself never steals focus.

## Feel

- Full QWERTY with a number row, `Esc`, `Tab`, `Del`, `Enter`, arrows, and an inverted-T-ish arrow cluster.
- **Shift** taps once for one character, twice to lock (Caps does the same lock); letter faces change case with the latch, symbol keys show their shifted faces.
- **Ctrl / Alt / Super** latch for the next key — tap `Ctrl` then `c` for a copy — and tap twice to hold them down for repeated chords.
- Held keys auto-repeat (characters, `Backspace`, `Del`, `Space`, arrows).
- Styled entirely from your active Omarchy theme: colors, corner rounding, spacing, and font all follow the shell.

## Install

```bash
omarchy plugin add https://github.com/ryanrhughes/omarchy-osk.git --enable
```

Or by hand: copy this folder to `~/.config/omarchy/plugins/ryan.osk/`, then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable ryan.osk
```

## CLI

```bash
omarchy-shell shell toggle ryan.osk '{}'   # toggle the keyboard
omarchy-shell osk toggle                   # same, via the plugin's own IPC target
omarchy-shell osk state                    # "open" or "closed"
```

Handy as a Hyprland binding in `~/.config/hypr/bindings.lua` if you want a hardware key to raise it too.
