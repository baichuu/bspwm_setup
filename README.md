# bspwm setup for Ubuntu Server

This script installs a bspwm desktop environment on Ubuntu Server with Xorg,
`bspwm`, `sxhkd`, Alacritty, Rofi, LXAppearance, Chromium, Picom, Dunst, Eww,
Zathura, Flameshot, Greenclip, Xclip, Neovim, Zsh, Eza, Node.js, npm, PipeWire,
PipeWire Pulse, WirePlumber, and a configured wallpaper.
It also explicitly installs the XKB libraries required by Alacritty:
`libxkbcommon0`, `libxkbcommon-x11-0`, and `xkb-data`.

The script does not install a display manager or modify the machine's network
configuration. Chromium is installed as a native `.deb` package from the
third-party [XtraDeb applications PPA](https://launchpad.net/~xtradeb/+archive/ubuntu/apps),
including its required setuid sandbox package, so the setup does not install or
use Snap/Snapd.

## Resource footprint

The installer uses the smaller `xserver-xorg` package instead of the full
`xorg` application bundle and installs all packages with
`--no-install-recommends`. It does not install a display manager or a full
desktop environment. Picom, Dunst, and the basic Eww bar are
lightweight background processes. Chromium remains the largest component and
will use significantly more memory only while it is running.

Papirus and Bibata add disk usage because they contain many icon and cursor
sizes, but they do not add background services or ongoing memory usage. The
small `librsvg2-common` runtime is installed explicitly so Rofi can render the
SVG application icons from Papirus on an Ubuntu minimal installation.
The variable Inter package is used instead of all static Inter weights to keep
the system UI font installation below approximately 1 MB.

Neovim is pinned to v0.11.7 and installed from its official architecture-
specific Linux tarball under `/opt/nvim-0.11.7`. Picom is pinned to the latest
stable release available when this setup was updated, v13, and is built with
the lightweight XRender feature set. Build dependencies are retained so later
source rebuilds do not need to download them again; temporary source and
download directories are removed.

The session is X11-only: it starts directly through Xorg, forces X11-compatible
application backends, and launches Chromium with `--ozone-platform=x11`. The
installer does not install or require Xwayland or a Wayland compositor.

## Installation

```bash
chmod +x install-bspwm.sh
sudo ./install-bspwm.sh
```

After installation, log out once, log in as a regular user on a TTY, and run
`startx`. The fresh login applies Zsh as that user's login shell with the same
path-and-command-duration prompt used on the source workstation. `Super +
Enter` also starts Alacritty directly in a Zsh login shell.

By default, the script configures the user who invoked `sudo`. If you are
logged in as root, specify a regular user explicitly:

```bash
sudo ./install-bspwm.sh --user username
```

Node.js and npm are installed from Ubuntu. Global npm packages are stored under
`~/.npm-global` and the npm cache under `~/.cache/npm`; the global binary
directory is already included in Zsh's `PATH`. Install global packages as the
regular user without `sudo`, for example:

```bash
npm install --global package-name
npm config get prefix
```

The second command should print the current user's `~/.npm-global` path. This
avoids permission errors caused by writing global packages into `/usr` or
`/usr/local`.

## Keybindings

- `Super + Enter`: open Alacritty.
- `Super + Space`: open the Rofi application launcher.
- `Super + W`: open Chromium.
- `Super + S`: open the four-action Flameshot screenshot menu.
- `Super + P`: open the styled power menu.
- `Super + V`: search the Greenclip clipboard history with Rofi.
- `Super + Q`: close the focused window.
- `Super + F`: toggle fullscreen for the focused window.
- `Super + Shift + Space`: toggle the focused window between tiled and
  floating states.
- `Super + M`: toggle the current workspace between tiled and monocle layout.
- `Alt + Tab`: focus the next window in the current workspace; add `Shift` to
  focus the previous window.
- `Super + H/J/K/L`: move window focus.
- `Super + Shift + H/J/K/L`: swap the focused window.
- `Super + Alt + H/J/K/L`: move a floating window by 24 pixels.
- `Super + Ctrl + H/J/K/L`: resize the focused window toward the selected edge
  by 24 pixels; this adjusts the split when the window is tiled.
- `Super + 1..3`: switch workspaces; add `Shift` to move the focused window.
- `Super + Shift + R`: reload Eww, sxhkd, and bspwm.
- Audio volume keys: change or mute the PipeWire default output.
- Brightness keys: change the display backlight in 5% steps.

Picom, Dunst, and Eww start automatically with bspwm. The Eww bar contains only
an Artix launcher button, an APT update count, bspwm workspaces, clock/date, hover-expandable
brightness and PipeWire volume controls, RAM/root-disk/CPU usage, a simple
always-visible system tray, and a power button. It deliberately excludes a dock, runcat, notification center,
window list, and theme selector. The launcher opens the styled Rofi drun mode;
the power button opens a four-row Rofi menu with left-aligned icon labels and
system uptime. All bundled Rofi menus use square corners. Feh applies the
bundled wallpaper whenever bspwm starts.

Greenclip v4.2 starts automatically and stores at most 50 clipboard entries.
Its text and small-image history uses the source workstation configuration;
Xclip is installed for X11 clipboard interoperability. The Greenclip process
and its static binary have a small resource footprint.

GTK2 and GTK3 applications use the bundled `siduck-onedark` theme,
`Papirus-Dark` icons, the Inter 11 UI font, and the `Bibata-Modern-Ice` cursor
at 24 px. Fontconfig also prefers Inter for generic sans-serif text used by
applications such as Chromium. Terminal, Rofi, Eww, and prompt fonts remain
Iosevka Nerd Font so their monospace layout and glyph icons are preserved.

Open **Customize Look and Feel** from the Rofi application launcher, or run
`lxappearance`, to change the GTK widget theme, colors, icon theme, mouse
cursor, and UI font graphically. The default selections installed by this
repository are `siduck-onedark`, `Papirus-Dark`, `Bibata-Modern-Ice`, and
Inter. LXAppearance is used without its Openbox plugin because this session
runs bspwm.

## Configuration files

Reusable application configurations live under `config/` and are copied into
the target user's `~/.config` directory during installation:

- `config/alacritty/alacritty.toml`: X11 terminal settings and a dark color
  palette based on the current workstation configuration.
- `config/bspwm/bspwmrc`: bspwm startup, three workspaces, borders, gaps, and
  bottom padding reserved for the Eww bar.
- `config/dunst/dunstrc`: compact top-center notifications using the same
  muted color palette and one bundled default icon without a randomizer script.
- `config/dunst/notification.png`: the default image used for notifications.
- `config/flameshot/flameshot.ini`: the source workstation's Flameshot toolbar,
  colors, PNG output, and screenshot-directory settings.
- `config/greenclip/greenclip.toml`: persistent text and image history limited
  to 50 clipboard entries.
- `config/npm/npmrc`: user-owned npm global prefix and cache paths.
- `config/eww`: a minimal Espresso-themed bar with an APT update counter,
  CPU/memory helpers, a Rofi power menu, and brightness/PipeWire controls.
- `config/fontconfig/50-inter-ui.conf`: selects Inter for generic sans-serif UI
  text, including Chromium's system-font fallback.
- `config/fonts/IosevkaNerdFont-Regular.ttf`: the single font weight required
  by the original Zsh prompt and Eww's Artix/power glyphs.
- `config/fonts/feather.ttf`: the small icon font used by Eww's update, disk,
  and memory indicators.
- `config/picom/picom.conf`: basic shadows without corner clipping, plus one normal
  window rule for open, close, and geometry animations on Picom v13.
- `config/rofi/launcher.rasi`: square Espresso application launcher based on
  the source workstation, with Papirus icons and only one red close glyph.
- `config/rofi/clipboard.rasi`: matching single-column Greenclip history menu.
- `config/rofi/screenshot.rasi` and `config/rofi/powermenu.rasi`: matching
  screenshot and uptime power menus with square corners.
- `config/sxhkd/sxhkdrc`: application, bspwm, audio, brightness, and reload
  keybindings.
- `config/zathura/zathurarc`: the current dark, recolored PDF-viewer theme and
  zoom bindings.
- `config/zsh/.zshrc`: a minimal colored path prompt with command duration and
  the original `` glyph and the source workstation's Eza listing/tree aliases,
  with no plugin manager or shell framework.
- `config/gtk-2.0/gtkrc` and `config/gtk-3.0/settings.ini`: select
  `siduck-onedark`, Inter 11, `Papirus-Dark`, and `Bibata-Modern-Ice`.
- `config/gtk-theme/siduck-onedark`: only the GTK2/GTK3 theme components needed
  by this setup; unrelated desktop-shell assets are excluded.
- `config/x11/Xresources`: applies the Bibata cursor to the X11 root window.
- `config/wallpaper/bspwm-wallpaper.png`: the wallpaper currently selected on
  the source workstation.

Eww is not distributed as an Ubuntu package. If it is missing, the installer
builds the official v0.6.0 source with X11-only support in `/tmp` and installs
the stripped binary. The temporary Rust toolchain is pinned to v1.77.2 for
compatibility with Eww's locked dependencies. Build packages are retained, but
the temporary Rust toolchain, Cargo cache, and source tree are removed.

Neovim v0.11.7 is installed from the official GitHub release tarball on amd64
and arm64 after verifying its upstream SHA-256 digest. Picom v13 is compiled
from the upstream release tag with XRender and animation support; unused
OpenGL, D-Bus, regex, documentation, and Compton-compatibility build options
are disabled.

## Vivado and OpenEye

Vivado and OpenEye are intentionally separate from the desktop installation.
For license-free synthesis and implementation reports, download the official
Vivado ML Standard 2025.2 Linux web installer as follows:

1. Open the [AMD Vivado 2025.2 download page](https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/development-tools/2025-2.html).
2. Confirm that the version selector at the top of the page shows `2025.2`.
3. Expand **Unified Installer for FPGA & Adaptive SoC Tools - 2025.2**.
4. Find **AMD Unified Installer for FPGAs & Adaptive SoCs 2025.2: Linux
   Self Extracting Web Installer**. It is the `BIN` download of approximately
   346.7 MB.
5. Click the blue Linux installer title and sign in to an AMD account when
   requested. Complete any AMD download or export-compliance form, then save
   the file in `~/Downloads`.
6. Do not download the Windows `EXE` or the approximately 95.68 GB `SFD`
   archive. The small Linux web installer downloads only the selected Vivado
   components and is much more suitable for a 256 GB SSD.

The downloaded filename should resemble
`FPGAs_AdaptiveSoCs_Unified_2025.2_..._Lin64.bin`. From this repository, run:

```bash
./install-vivado.sh ~/Downloads/FPGAs_AdaptiveSoCs_Unified_2025.2_*_Lin64.bin
```

Run the script as the regular X11 user from an Alacritty terminal, not with
`sudo`. Enter the sudo password only when the script installs Ubuntu libraries.
Use the following choices in the AMD installer:

1. On **Select Install Type**, choose **Download and Install Now**.
2. On **Select Product to Install**, choose **Vivado**, not Vitis, Vitis
   Embedded Development, BootGen, Lab Edition, or Hardware Server.
3. On **Select Edition to Install**, choose **Vivado ML Standard**. Do not
   choose **Vivado ML Enterprise**: the project does not need its paid device
   coverage. If the customization page title says `Vivado ML Enterprise`, go
   back and correct this selection before continuing.
4. On the customization page, keep **Design Tools > Vivado** selected. Clear
   Vitis HLS, Vitis Networking P4, Vitis Model Composer, Vitis Embedded
   Development, Power Design Manager, and DocNav.
5. Under **Devices**, expand **SoCs** and select only **Zynq UltraScale+ MPSoC**.
   Clear Alveo/edge platforms, Kria SOMs, 7 Series, UltraScale, UltraScale+,
   Versal Adaptive SoCs, and Engineering Sample Devices. This installs the
   XCZU1-XCZU7 support needed for the provisional XCZU7EV target without all
   Enterprise device families.
6. Clear **Acquire or Manage a License Key**. ML Standard does not need a FLEX
   license. Linux cable drivers can remain unselected for report-only work.
7. In **Select the installation directory**, enter the absolute path to the
   regular user's home, for example `/home/baichu/AMD`. Do not leave it blank;
   avoid `~`, spaces, `/root`, and a path owned by root.
8. Desktop and program-group shortcuts are optional because this repository
   creates its own `AMD Vivado 2025.2` Rofi launcher after installation.
9. Before starting the download, verify that the summary says **Vivado ML
   Standard**, not Enterprise, and that only the required MPSoC device support
   is selected. If it still estimates roughly 72 GB as in the Enterprise
   selection, go back and remove the unwanted edition, tools, and devices.

Standard 2025.2 does not require a FLEX license and supports XCZU1 through
XCZU7 devices, but not the ZU19EG used by the OpenEye paper. After installation,
the script creates an `AMD Vivado 2025.2` desktop entry for Rofi. It can also be
started from a terminal with:

```bash
source ~/.config/vivado/settings64.sh
vivado
```

Install the pinned OpenEye RTL and Python environment separately:

```bash
./install-openeye.sh
```

This installs Icarus Verilog, Verilator, and GTKWave, clones OpenEye to
`~/Projects/OpenEye`, and uses `uv` to create `.venv` and install all Python
dependencies. It does not install Vitis or PetaLinux.
