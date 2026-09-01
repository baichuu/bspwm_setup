# bspwm setup for Ubuntu Server

This script installs a bspwm desktop environment on Ubuntu Server with Xorg,
`bspwm`, `sxhkd`, Alacritty, Rofi, LXAppearance, Chromium, Picom, Dunst, Eww,
Zathura, Flameshot, Greenclip, Xclip, Neovim, Zsh, Eza, Node.js, npm, PipeWire,
PipeWire Pulse, WirePlumber, rclone, and a configured wallpaper.
It also explicitly installs the XKB libraries required by Alacritty:
`libxkbcommon0`, `libxkbcommon-x11-0`, and `xkb-data`.

The script does not install a display manager or modify the machine's network
configuration. Chromium is installed as a native `.deb` package from the
third-party [XtraDeb applications PPA](https://launchpad.net/~xtradeb/+archive/ubuntu/apps),
including its required setuid sandbox package, so the setup does not install or
use Snap/Snapd.

## Support and important notes

This repository is intended only for a minimal **Ubuntu Server 24.04 LTS
x86-64** installation. The scripts explicitly reject non-Ubuntu systems and
are not supported on Ubuntu Desktop, Debian, Arch, WSL, ARM machines, or an
existing Wayland desktop. A fresh Ubuntu Server installation is recommended;
using it on an already customized desktop may replace assumptions made by the
current session and user configuration.

Before installing, note the following:

- Use a regular local user with `sudo` access and a working internet
  connection. Run `install-bspwm.sh` with `sudo`, but run `install-vivado.sh`
  and `install-openeye.sh` as the regular user without `sudo`.
- The desktop is X11-only. It deliberately does not install Xwayland, a
  Wayland compositor, or a display manager. Start the session from a TTY with
  `startx` after logging out and back in once.
- Touchpads use the Xorg libinput driver with tap-to-click enabled. One-, two-,
  and three-finger taps map to left, right, and middle click respectively.
  Restart the Xorg session after changing
  `config/x11/90-touchpad-tapping.conf`; reloading bspwm alone is insufficient.
- Snapd is neither installed nor required. Chromium comes from XtraDeb, while
  some pinned programs are downloaded or built from their upstream projects.
  Review these external sources if the machine has strict supply-chain rules.
- Keep this repository in a permanent, user-readable location after
  installation. Active dotfiles are symlinks into `config/`; moving the repo
  makes those links invalid.
- Existing config destinations are preserved as timestamped `.bak.*` paths,
  but settings are not automatically merged. Review the backups before
  removing them.
- The setup aims to stay lightweight, but Vivado is not lightweight. Keep at
  least 100 GiB free before installing it; a 256 GB SSD requires selecting only
  the needed Vivado edition, tools, and device family.
- The desktop installer may allocate disk space for a swap file so total active
  swap reaches approximately 8 GiB. It never manages host swap from inside a
  container.
- Audio, brightness control, the system tray, and hardware acceleration still
  depend on the laptop firmware, kernel drivers, Xorg driver, and user session.
  The container test can verify packages and builds, but it cannot validate
  these hardware-dependent features or the Vivado GUI.
- The AMD web installer requires an AMD account and interactive acceptance of
  its download terms. This repository cannot embed credentials or bypass that
  step.

Ubuntu 24.04 does not provide `eza` in the enabled minimal-server package
sources used by this setup. The installer therefore downloads the pinned Eza
v0.23.5 x86-64 release directly from the upstream project, verifies its
SHA-256 checksum, installs it under `/usr/local/bin`, and checks the reported
version before configuring the shell aliases.

The scripts and configuration have been syntax-checked, but the complete
installer has intentionally not been run on the development workstation: a
full run installs system packages, creates swap, and changes the desktop
session. Perform the final end-to-end test on a fresh Ubuntu Server target or a
disposable test machine before relying on it for important work.

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

For large Vivado runs, the installer ensures that total active swap is at least
approximately 8 GiB. It preserves existing swap and creates only the missing
capacity in `/swapfile-bspwm-setup`, retains a 2 GiB disk safety margin, adds
the file to `/etc/fstab`, and sets `vm.swappiness=20` to prefer RAM. Swap setup
is skipped inside containers because a container cannot manage host swap.

## Installation

```bash
chmod +x install-bspwm.sh
sudo ./install-bspwm.sh
```

Desktop configuration is installed as absolute symbolic links back into this
repository instead of being copied. For example, `~/.config/bspwm` points to
`config/bspwm`, and the same applies to Alacritty, Dunst, Eww, Flameshot,
Picom, Rofi, sxhkd, Zathura, GTK, shell, font, theme, and wallpaper files.
Editing a tracked file here therefore updates the active configuration
immediately; reload the relevant program when it does not watch files itself.

Keep this repository at its installed location after setup, because moving or
deleting it breaks those links. When a destination already exists and is not
the expected link, the installer preserves it beside the original name as a
timestamped `.bak.YYYYMMDD-HHMMSS` path before creating the link. System files
such as the swap sysctl setting remain regular copies under `/etc`, since they
must be available independently of the user's home directory.

The touchpad file is the exception among `/etc` settings: the installer links
`/etc/X11/xorg.conf.d/90-touchpad-tapping.conf` back into this repository so it
can be maintained with the other desktop configuration. The link is owned by
root, but its target remains editable by the repository owner.

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

rclone is installed from Ubuntu and its executable is verified during setup.
Cloud credentials are deliberately not embedded in this repository. Configure
a remote interactively as the regular user, then verify it:

```bash
rclone config
rclone version
rclone listremotes
swapon --show
```

## Applying and checking later patches

The desktop link manifest and source-file validation live in
`lib/config-links.sh`. Both the full installer and the maintenance tools use
this single manifest, so adding or moving a configuration target only needs to
be recorded once.

After pulling or editing a patch, first run the read-only source check:

```bash
./check-setup.sh --sources-only
```

On an installed machine, run the complete health check to verify every
symlink, required command, pinned Eza/Neovim/Picom versions, swap capacity,
and the optional Vivado/OpenEye artifacts:

```bash
./check-setup.sh
```

If a patch adds a new link or an existing link was replaced, reapply only the
configuration layer:

```bash
sudo ./apply-config.sh
```

This command does not run APT, compile software, configure swap, or touch the
Vivado/OpenEye installations. It preserves any unexpected destination as a
timestamped backup before recreating the link. Press `Super + Shift + R` to
reload Eww, sxhkd, and bspwm. Restart individual applications for their own
configuration changes, and restart the entire Xorg session after modifying
the touchpad InputClass file.

Before committing a maintenance patch, use:

```bash
bash -n install-bspwm.sh install-vivado.sh install-openeye.sh \
  apply-config.sh check-setup.sh lib/config-links.sh
git diff --check
./check-setup.sh --sources-only
```

`--sources-only` already performs the shell syntax and Git whitespace checks;
the expanded commands above are included so a failure can be reproduced
directly.

Use `--config-only` instead when checking symlinks on an installed machine
without checking packages, running processes, versions, swap, Vivado, or
OpenEye.

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
- `config/x11/90-touchpad-tapping.conf`: enables libinput tap-to-click with
  left/right/middle one-, two-, and three-finger tap mapping.
- `config/x11/xinitrc`: starts the X11-only bspwm session and exports its GTK,
  Qt, cursor, and shell environment.
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

The script warns when the installation filesystem has less than 100 GiB free.
This is a warning rather than an automatic deletion or cleanup operation.

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

The installer also creates `~/.local/bin/vivado-batch`. Run a Tcl flow from
any working directory with:

```bash
vivado-batch path/to/flow.tcl optional-tcl-arguments
```

The helper sources the installed 2025.2 environment, runs Vivado with
`-mode batch`, and leaves `vivado.log` and `vivado.jou` in the current working
directory.

Install the pinned OpenEye RTL and Python environment separately:

```bash
./install-openeye.sh
```

This installs Icarus Verilog, Verilator, and GTKWave, clones OpenEye to
`~/Projects/OpenEye`, and uses `uv` to create `.venv` and install all Python
dependencies. It then checks the Python dependency graph and automatically runs
the upstream `test/cocotb_PE` smoke test with Icarus Verilog. A failed PE build
or test stops the installer immediately.

After the smoke test passes, the installer creates two locally excluded files
inside the OpenEye checkout:

- `environment.json`: generation time, Ubuntu/kernel details, virtualenv Python,
  Icarus and Verilator versions, pinned OpenEye repository/commit, and detected
  Vivado version.
- `requirements.lock.txt`: exact installed Python dependency versions generated
  by `uv pip freeze --strict --exclude-editable`. The editable OpenEye package
  is represented by its pinned Git commit in `environment.json`.

Install Vivado before OpenEye when possible so the manifest records Vivado
2025.2 instead of `not installed`. Neither artifact changes upstream OpenEye's
Git status because both names are added to `.git/info/exclude`. This setup does
not install Vitis or PetaLinux.
