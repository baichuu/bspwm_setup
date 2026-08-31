# bspwm setup for Ubuntu Server

This script installs a bspwm desktop environment on Ubuntu Server with Xorg,
`bspwm`, `sxhkd`, Alacritty, Rofi, Chromium, Picom, Dunst, Eww, Zathura,
Neovim, Zsh, PipeWire, PipeWire Pulse, WirePlumber, and a configured wallpaper.
It also explicitly installs the XKB libraries required by Alacritty:
`libxkbcommon0`, `libxkbcommon-x11-0`, and `xkb-data`.

The script does not install a display manager or modify the machine's network
configuration. Chromium is installed as a native `.deb` package from the
third-party [XtraDeb applications PPA](https://launchpad.net/~xtradeb/+archive/ubuntu/apps),
so the setup does not install or use Snap/Snapd.

## Resource footprint

The installer uses the smaller `xserver-xorg` package instead of the full
`xorg` application bundle and installs all packages with
`--no-install-recommends`. It does not install a display manager or a full
desktop environment. Picom, Dunst, and the basic Eww bar are
lightweight background processes. Chromium remains the largest component and
will use significantly more memory only while it is running.

Papirus and Bibata add disk usage because they contain many icon and cursor
sizes, but they do not add background services or ongoing memory usage.

Neovim is pinned to v0.11.7 and installed from its official architecture-
specific Linux tarball under `/opt/nvim-0.11.7`. Picom is pinned to the latest
stable release available when this setup was updated, v13, and is built with
the lightweight XRender feature set. Picom's temporary compiler packages and
both projects' download/source directories are removed after installation.

The session is X11-only: it starts directly through Xorg, forces X11-compatible
application backends, and launches Chromium with `--ozone-platform=x11`. The
installer does not install or require Xwayland or a Wayland compositor.

## Installation

```bash
chmod +x install-bspwm.sh
sudo ./install-bspwm.sh
```

After installation, log in as a regular user on a TTY and run `startx`.
Zsh is set as that user's login shell with the same path-and-command-duration
prompt used on the source workstation.

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
- `Super + 1..3`: switch workspaces; add `Shift` to move the focused window.
- `Super + Shift + R`: reload Eww, sxhkd, and bspwm.
- Audio volume keys: change or mute the PipeWire default output.
- Brightness keys: change the display backlight in 5% steps.

Picom, Dunst, and Eww start automatically with bspwm. The Eww bar contains only
an Artix launcher button, an APT update count, bspwm workspaces, clock/date, hover-expandable
brightness and PipeWire volume controls, RAM/root-disk/CPU usage, a simple
always-visible system tray, and a power button. It deliberately excludes a dock, runcat, notification center,
window list, and theme selector. The launcher opens the regular Rofi drun mode;
the power button opens a simple unstyled Rofi menu. Feh applies the bundled
wallpaper whenever bspwm starts.

GTK2 and GTK3 applications use the bundled `siduck-onedark` theme,
`Papirus-Dark` icons, and the `Bibata-Modern-Ice` cursor at 24 px.

## Configuration files

Reusable application configurations live under `config/` and are copied into
the target user's `~/.config` directory during installation:

- `config/alacritty/alacritty.toml`: X11 terminal settings and a dark color
  palette based on the current workstation configuration.
- `config/dunst/dunstrc`: compact top-center notifications using the same
  muted color palette and one bundled default icon without a randomizer script.
- `config/dunst/notification.png`: the default image used for notifications.
- `config/eww`: a minimal Espresso-themed bar with an APT update counter,
  CPU/memory helpers, a Rofi power menu, and brightness/PipeWire controls.
- `config/fonts/IosevkaNerdFont-Regular.ttf`: the single font weight required
  by the original Zsh prompt and Eww's Artix/power glyphs.
- `config/fonts/feather.ttf`: the small icon font used by Eww's update, disk,
  and memory indicators.
- `config/picom/picom.conf`: basic shadows and rounded corners, plus one normal
  window rule for open, close, and geometry animations on Picom v13.
- `config/zathura/zathurarc`: the current dark, recolored PDF-viewer theme and
  zoom bindings.
- `config/zsh/.zshrc`: a minimal colored path prompt with command duration and
  the original `` glyph, with no plugin manager, aliases, or shell framework.
- `config/gtk-2.0/gtkrc` and `config/gtk-3.0/settings.ini`: select
  `siduck-onedark`, `Papirus-Dark`, and `Bibata-Modern-Ice`.
- `config/gtk-theme/siduck-onedark`: only the GTK2/GTK3 theme components needed
  by this setup; unrelated desktop-shell assets are excluded.
- `config/x11/Xresources`: applies the Bibata cursor to the X11 root window.
- `config/wallpaper/bspwm-wallpaper.png`: the wallpaper currently selected on
  the source workstation.

Eww is not distributed as an Ubuntu package. If it is missing, the installer
builds the official v0.6.0 source with X11-only support in `/tmp`, installs only
the stripped binary, then removes packages that were added solely for the
build. Rust, Cargo, and the source tree are not retained.

Neovim v0.11.7 is installed from the official GitHub release tarball on amd64
and arm64 after verifying its upstream SHA-256 digest. Picom v13 is compiled
from the upstream release tag with XRender and animation support; unused
OpenGL, D-Bus, regex, documentation, and Compton-compatibility build options
are disabled.
