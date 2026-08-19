# On-Screen Keyboard for Omarchy

A touch-friendly on-screen keyboard for tablets and touchscreen machines, built as an [Omarchy](https://omarchy.org) shell plugin.

A small keyboard button sits in the bottom-right corner of the screen at all times. Tap it and a full QWERTY keyboard rises from the bottom edge. A slim handle strip runs along the keyboard's top edge with a ✕ close button at its top-right corner; the keyboard-off key on the board does the same. Closing it brings the button back.

The keyboard has two modes, switched from the handle strip:

- **Docked** (default) — the keyboard reserves its space at the bottom of the screen, so tiled windows shrink above it and the focused input never hides behind the keys.
- **Floating** — the keyboard reserves nothing and sits above your windows; drag it anywhere by its handle. Dragging the handle while docked tears the keyboard off into floating mode.

The mode and float position are remembered across sessions.

Keys are injected with `wtype` (part of Omarchy's base package set), so the keyboard types into whichever window has focus, exactly like a hardware keyboard. The keyboard itself never steals focus.

## Feel

- Full QWERTY with a number row, `Esc`, `Tab`, `Del`, `Enter`, arrows, and an inverted-T-ish arrow cluster.
- **Shift** taps once for one character, twice to lock (Caps does the same lock); letter faces change case with the latch, symbol keys show their shifted faces.
- **Ctrl / Alt / Super** latch for the next key — tap `Ctrl` then `c` for a copy — and tap twice to hold them down for repeated chords.
- **Super chords trigger your real Hyprland binds** — tap `Super` then `Space` for the Omarchy menu, `Super` then a digit to switch workspaces. (Under the hood, Hyprland's bind matching resolves virtual-keyboard keycodes against the hardware keymap, so the keyboard pads each `wtype` invocation with release-only dummy events to park every keysym at its true evdev keycode. The keycode table assumes a US layout; chords may hit the wrong bind on other layouts until the compositor matches by the source device's keymap.)
- Held keys auto-repeat (characters, `Backspace`, `Del`, `Space`, arrows).
- Styled entirely from your active Omarchy theme: colors, corner rounding, spacing, and font all follow the shell.

## Install

```bash
omarchy plugin add https://github.com/ryanrhughes/omarchy-osk.git --enable
```

Or by hand: copy this folder to `~/.config/omarchy/plugins/ryanrhughes.osk/`, then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable ryanrhughes.osk
```

## CLI

```bash
omarchy-shell shell toggle ryanrhughes.osk '{}'   # toggle the keyboard
omarchy-shell osk toggle                          # same, via the plugin's own IPC target
omarchy-shell osk state                           # "open" or "closed"
omarchy-shell osk mode                            # "docked" or "floating"
omarchy-shell osk dock                            # dock to the bottom edge
omarchy-shell osk undock                          # float at the last float position
omarchy-shell osk moveTo 100 200                  # float at left=100, bottom=200
```

Handy as a Hyprland binding in `~/.config/hypr/bindings.lua` if you want a hardware key to raise it too.

After `omarchy plugin update`, run `omarchy-restart-shell` to make sure the new plugin code is actually loaded — the shell's hot reload does not reliably swap panel code yet.
