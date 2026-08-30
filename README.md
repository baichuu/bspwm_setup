# bspwm setup for Ubuntu Server

This script installs a bspwm desktop environment on Ubuntu Server with Xorg,
`bspwm`, `sxhkd`, Alacritty, Rofi, Chromium, Picom, Dunst, and a basic Polybar
configuration. It also explicitly installs the XKB libraries required by
Alacritty: `libxkbcommon0`, `libxkbcommon-x11-0`, and `xkb-data`.

The script does not install a display manager or modify the machine's network
configuration.

## Installation

```bash
chmod +x install-bspwm.sh
sudo ./install-bspwm.sh
```

After installation, log in as a regular user on a TTY and run `startx`.

By default, the script configures the user who invoked `sudo`. If you are
logged in as root, specify a regular user explicitly:

```bash
sudo ./install-bspwm.sh --user username
```

## Keybindings

- `Super + Enter`: open Alacritty.
- `Super + Space`: open the Rofi application launcher.
- `Super + B`: open Chromium.
- `Super + Q`: close the focused window.
- `Super + H/J/K/L`: move window focus.
- `Super + Shift + H/J/K/L`: swap the focused window.
- `Super + 1..0`: switch workspaces; add `Shift` to move the focused window.
- `Super + Shift + R`: reload the sxhkd and bspwm configurations.

Picom, Dunst, and Polybar start automatically with bspwm. Polybar displays the
workspaces, focused window title, CPU usage, memory usage, and time.
