#!/usr/bin/env bash

# Shared dotfile manifest. Callers must define SCRIPT_DIR, target_user,
# target_group, target_home, log, warn, and die before invoking these functions.

desktop_config_sources() {
  cat <<'EOF'
config/alacritty/alacritty.toml
config/bspwm/bspwmrc
config/dunst/dunstrc
config/dunst/notification.png
config/eww/eww.scss
config/eww/eww.yuck
config/eww/scripts/brightness-control
config/eww/scripts/cpu
config/eww/scripts/memory
config/eww/scripts/powermenu
config/eww/scripts/screenshot
config/eww/scripts/updates
config/eww/scripts/volume-status
config/flameshot/flameshot.ini
config/fontconfig/50-inter-ui.conf
config/fonts/IosevkaNerdFont-Regular.ttf
config/fonts/feather.ttf
config/greenclip/greenclip.toml
config/gtk-2.0/gtkrc
config/gtk-3.0/settings.ini
config/gtk-theme/siduck-onedark/index.theme
config/npm/npmrc
config/picom/picom.conf
config/rofi/clipboard.rasi
config/rofi/launcher.rasi
config/rofi/powermenu.rasi
config/rofi/screenshot.rasi
config/sxhkd/sxhkdrc
config/system/99-bspwm-setup-swap.conf
config/vivado/vivado-batch
config/wallpaper/bspwm-wallpaper.png
config/x11/90-touchpad-tapping.conf
config/x11/Xresources
config/x11/xinitrc
config/zathura/zathurarc
config/zsh/.zshrc
EOF
}

desktop_config_links() {
  local config_dir="$target_home/.config"

  cat <<EOF
$SCRIPT_DIR/config/x11/90-touchpad-tapping.conf|/etc/X11/xorg.conf.d/90-touchpad-tapping.conf|root:root
$SCRIPT_DIR/config/bspwm|$config_dir/bspwm|$target_user:$target_group
$SCRIPT_DIR/config/sxhkd|$config_dir/sxhkd|$target_user:$target_group
$SCRIPT_DIR/config/alacritty|$config_dir/alacritty|$target_user:$target_group
$SCRIPT_DIR/config/dunst|$config_dir/dunst|$target_user:$target_group
$SCRIPT_DIR/config/flameshot|$config_dir/flameshot|$target_user:$target_group
$SCRIPT_DIR/config/greenclip/greenclip.toml|$config_dir/greenclip.toml|$target_user:$target_group
$SCRIPT_DIR/config/picom|$config_dir/picom|$target_user:$target_group
$SCRIPT_DIR/config/rofi|$config_dir/rofi|$target_user:$target_group
$SCRIPT_DIR/config/eww|$config_dir/eww|$target_user:$target_group
$SCRIPT_DIR/config/zathura|$config_dir/zathura|$target_user:$target_group
$SCRIPT_DIR/config/gtk-3.0|$config_dir/gtk-3.0|$target_user:$target_group
$SCRIPT_DIR/config/fontconfig/50-inter-ui.conf|$config_dir/fontconfig/conf.d/50-inter-ui.conf|$target_user:$target_group
$SCRIPT_DIR/config/gtk-2.0/gtkrc|$target_home/.gtkrc-2.0|$target_user:$target_group
$SCRIPT_DIR/config/npm/npmrc|$target_home/.npmrc|$target_user:$target_group
$SCRIPT_DIR/config/zsh/.zshrc|$target_home/.zshrc|$target_user:$target_group
$SCRIPT_DIR/config/x11/Xresources|$target_home/.Xresources|$target_user:$target_group
$SCRIPT_DIR/config/x11/xinitrc|$target_home/.xinitrc|$target_user:$target_group
$SCRIPT_DIR/config/wallpaper/bspwm-wallpaper.png|$target_home/.local/share/backgrounds/bspwm-wallpaper.png|$target_user:$target_group
$SCRIPT_DIR/config/gtk-theme/siduck-onedark|$target_home/.themes/siduck-onedark|$target_user:$target_group
$SCRIPT_DIR/config/fonts/IosevkaNerdFont-Regular.ttf|$target_home/.local/share/fonts/Iosevka/IosevkaNerdFont-Regular.ttf|$target_user:$target_group
$SCRIPT_DIR/config/fonts/feather.ttf|$target_home/.local/share/fonts/Icons/feather.ttf|$target_user:$target_group
EOF
}

validate_desktop_config_sources() {
  local relative

  while IFS= read -r relative; do
    [[ -n $relative ]] || continue
    [[ -r $SCRIPT_DIR/$relative ]] || die "Missing configuration file: $relative"
  done < <(desktop_config_sources)
}

link_repo_config() {
  local source=$1
  local target=$2
  local link_owner=$3
  local backup

  [[ -e $source || -L $source ]] || die "Configuration source does not exist: $source"
  mkdir -p -- "$(dirname -- "$target")"

  if [[ -L $target && $(readlink -- "$target") == "$source" ]]; then
    chown -h "$link_owner" "$target"
    return
  fi

  if [[ -e $target || -L $target ]]; then
    backup="$target.bak.$(date +%Y%m%d-%H%M%S)"
    while [[ -e $backup || -L $backup ]]; do
      backup="$backup.1"
    done
    mv -- "$target" "$backup"
    warn "Moved existing configuration to: $backup"
  fi

  ln -s -- "$source" "$target"
  chown -h "$link_owner" "$target"
}

install_desktop_config_links() {
  local source
  local target
  local owner

  validate_desktop_config_sources
  install -d -m 0755 -o "$target_user" -g "$target_group" \
    "$target_home/.config" \
    "$target_home/.config/fontconfig/conf.d" \
    "$target_home/.local" \
    "$target_home/.local/share" \
    "$target_home/.local/share/backgrounds" \
    "$target_home/.local/share/fonts" \
    "$target_home/.local/share/fonts/Iosevka" \
    "$target_home/.local/share/fonts/Icons" \
    "$target_home/.cache" \
    "$target_home/.cache/npm" \
    "$target_home/.npm-global" \
    "$target_home/.npm-global/bin" \
    "$target_home/Pictures" \
    "$target_home/Pictures/Screenshots" \
    "$target_home/.themes"
  install -d -m 0755 /etc/X11/xorg.conf.d

  while IFS='|' read -r source target owner; do
    [[ -n $source ]] || continue
    link_repo_config "$source" "$target" "$owner"
  done < <(desktop_config_links)

  chown -R "$target_user:$target_group" \
    "$target_home/.cache/npm" \
    "$target_home/.npm-global"
}
