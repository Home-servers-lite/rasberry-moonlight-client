#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"

MOONLIGHT_REPO_BASE_URL="https://dl.cloudsmith.io/public/moonlight-game-streaming/moonlight-qt/deb/raspbian"
MOONLIGHT_KEYRING_PATH="/usr/share/keyrings/moonlight-game-streaming-moonlight-qt-archive-keyring.gpg"
MOONLIGHT_SOURCE_LIST_PATH="/etc/apt/sources.list.d/moonlight-game-streaming-moonlight-qt.list"
VENDORED_CLOUDSMITH_SETUP_SCRIPT="$REPO_ROOT/vendor/cloudsmith/setup.deb.sh"
VENDORED_CLOUDSMITH_GPG_KEY="$REPO_ROOT/vendor/cloudsmith/gpg.2F6AE14E1C660D44.key"
VENDORED_CLOUDSMITH_SETUP_SHA256="f309187cea9dd45cd36f542e38cd84d415d5c1ef8972a8a2b9d49cdecb3d84a3"
VENDORED_CLOUDSMITH_GPG_SHA256="e3015be2637545f6aae825032c5d4e02b65f5b6d32010cbd4eab2cc4744d3dac"

AUTOSTART=0
INSTALL_VIRTUALHERE=0
LITE_AUDIO=0
CONFIGURE_4K60=0
CONFIGURE_BOOT=1
CONFIGURE_GROUPS=1
CONFIGURE_AUTOLOGIN=1
FULL_KMS=1
UPGRADE=1
REBOOT=0
DRY_RUN=0
REMOVE_AUTOSTART=0
RESTORE_BOOT_CONFIG=0
HOST=""
APP=""
TARGET_USER="${MOONLIGHT_USER:-}"
VIRTUALHERE_BINARY=""

usage() {
  cat <<'EOF'
Usage:
  setup-moonlight-pi.sh [options]

Installs and configures Moonlight Qt on Raspberry Pi OS.

Options:
  --autostart          Boot to console autologin and start Moonlight on TTY1.
  --host HOST          Host IP/hostname for direct streaming.
  --app APP            App name for direct streaming, e.g. "Desktop".
  --virtualhere        Install VirtualHere USB-over-IP server from a local binary.
  --virtualhere-binary PATH
                       Local VirtualHere server binary to install. Nothing is downloaded.
  --lite-audio         Install PulseAudio for Raspberry Pi OS Lite.
  --4k60               Add gpu_mem=128 for 4K/60 decoder stability.
  --no-boot-config     Do not edit /boot/firmware/config.txt or /boot/config.txt.
  --no-groups          Do not add the user to input/video/render/audio groups.
  --no-autologin       Do not change boot behavior with raspi-config.
  --skip-upgrade       Skip apt upgrade.
  --skip-kms           Do not add the Full KMS boot config block.
  --user USER          User to configure for groups/autostart.
  --remove-autostart   Remove the managed TTY1 autostart block and exit.
  --restore-boot-config
                       Remove the managed boot config block and exit.
  --reboot             Reboot automatically after setup.
  --no-reboot          Do not reboot automatically. This is the default.
  --dry-run            Print the commands without changing the system.
  -h, --help           Show this help.

Examples:
  bash scripts/setup-moonlight-pi.sh
  bash scripts/setup-moonlight-pi.sh --autostart --lite-audio
  bash scripts/setup-moonlight-pi.sh --autostart --host 192.168.1.50 --app "Desktop"
  bash scripts/setup-moonlight-pi.sh --no-boot-config --no-groups --no-autologin
  bash scripts/setup-moonlight-pi.sh --virtualhere --virtualhere-binary ./vhusbdarm64
  bash scripts/setup-moonlight-pi.sh --remove-autostart
  bash scripts/setup-moonlight-pi.sh --restore-boot-config
EOF
}

log() {
  printf '[moonlight-pi] %s\n' "$*"
}

warn() {
  printf '[moonlight-pi] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[moonlight-pi] ERROR: %s\n' "$*" >&2
  exit 1
}

run() {
  if (( DRY_RUN )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

sudo_run() {
  if (( EUID == 0 )); then
    run "$@"
  else
    run sudo "$@"
  fi
}

parse_args() {
  while (($#)); do
    case "$1" in
      --autostart)
        AUTOSTART=1
        ;;
      --host)
        shift
        [[ $# -gt 0 ]] || die "--host requires a value"
        HOST="$1"
        ;;
      --app)
        shift
        [[ $# -gt 0 ]] || die "--app requires a value"
        APP="$1"
        ;;
      --virtualhere)
        INSTALL_VIRTUALHERE=1
        ;;
      --virtualhere-binary)
        shift
        [[ $# -gt 0 ]] || die "--virtualhere-binary requires a value"
        VIRTUALHERE_BINARY="$1"
        ;;
      --lite-audio)
        LITE_AUDIO=1
        ;;
      --4k60)
        CONFIGURE_4K60=1
        ;;
      --no-boot-config)
        CONFIGURE_BOOT=0
        ;;
      --no-groups)
        CONFIGURE_GROUPS=0
        ;;
      --no-autologin)
        CONFIGURE_AUTOLOGIN=0
        ;;
      --skip-upgrade)
        UPGRADE=0
        ;;
      --skip-kms)
        FULL_KMS=0
        ;;
      --user)
        shift
        [[ $# -gt 0 ]] || die "--user requires a value"
        TARGET_USER="$1"
        ;;
      --remove-autostart)
        REMOVE_AUTOSTART=1
        ;;
      --restore-boot-config)
        RESTORE_BOOT_CONFIG=1
        ;;
      --reboot)
        REBOOT=1
        ;;
      --no-reboot)
        REBOOT=0
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done

  if [[ -n "$APP" && -z "$HOST" ]]; then
    die "--app requires --host"
  fi

  if (( INSTALL_VIRTUALHERE )) && [[ -z "$VIRTUALHERE_BINARY" ]]; then
    die "--virtualhere requires --virtualhere-binary PATH. The installer does not download VirtualHere scripts or binaries."
  fi

  if (( CONFIGURE_BOOT == 0 && CONFIGURE_4K60 == 1 )); then
    warn "--no-boot-config is set, so --4k60 will not change boot config."
  fi
}

calculate_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  die "sha256sum or shasum is required to verify vendored files"
}

verify_file_sha256() {
  local file="$1"
  local expected="$2"
  local actual

  [[ -f "$file" ]] || die "Required vendored file is missing: $file"

  actual="$(calculate_sha256 "$file")"
  if [[ "$actual" != "$expected" ]]; then
    die "Checksum mismatch for $file. Expected $expected but got $actual"
  fi
}

detect_target_user() {
  if [[ -n "$TARGET_USER" ]]; then
    printf '%s\n' "$TARGET_USER"
    return
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi

  local login_user
  login_user="$(logname 2>/dev/null || true)"
  if [[ -n "$login_user" && "$login_user" != "root" ]]; then
    printf '%s\n' "$login_user"
    return
  fi

  id -un
}

detect_user_home() {
  if command -v getent >/dev/null 2>&1; then
    getent passwd "$TARGET_USER" | cut -d: -f6
    return
  fi

  if command -v dscl >/dev/null 2>&1; then
    dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
    return
  fi

  printf '%s\n' "${HOME:-}"
}

detect_user_shell() {
  if command -v getent >/dev/null 2>&1; then
    getent passwd "$TARGET_USER" | cut -d: -f7
    return
  fi

  if command -v dscl >/dev/null 2>&1; then
    dscl . -read "/Users/$TARGET_USER" UserShell 2>/dev/null | awk '{print $2}'
    return
  fi

  printf '%s\n' "${SHELL:-/bin/sh}"
}

detect_codename() {
  if [[ -n "${MOONLIGHT_CODENAME:-}" ]]; then
    printf '%s\n' "$MOONLIGHT_CODENAME"
    return
  fi

  if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -cs
    return
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s\n' "${VERSION_CODENAME:-}"
    return
  fi
}

detect_boot_config() {
  local candidate
  for candidate in /boot/firmware/config.txt /boot/config.txt; do
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

print_environment_note() {
  if [[ -r /proc/device-tree/model ]]; then
    local model
    model="$(tr -d '\0' < /proc/device-tree/model)"
    log "Detected hardware: $model"
    if [[ "$model" != *"Raspberry Pi"* ]]; then
      warn "This does not look like Raspberry Pi hardware."
    fi
  else
    warn "Cannot read /proc/device-tree/model; continuing anyway."
  fi
}

install_moonlight() {
  log "Installing base packages..."
  sudo_run apt-get update
  sudo_run apt-get install -y apt-transport-https ca-certificates gnupg lsb-release

  local codename
  codename="$(detect_codename)"
  [[ -n "$codename" ]] || die "Could not detect Debian/Raspberry Pi OS codename"

  case "$codename" in
    bookworm|trixie|forky)
      ;;
    *)
      warn "Official Raspberry Pi instructions target Raspberry Pi OS 12 Bookworm or later; detected '$codename'."
      ;;
  esac

  install_moonlight_repository "$codename"

  log "Installing Moonlight Qt..."
  sudo_run apt-get update

  local packages=(moonlight-qt)
  if (( LITE_AUDIO )); then
    packages+=(pulseaudio)
  fi

  sudo_run apt-get install -y "${packages[@]}"

  if (( UPGRADE )); then
    log "Upgrading installed packages..."
    sudo_run apt-get upgrade -y
  fi
}

install_moonlight_repository() {
  local codename="$1"
  local keyring_tmp source_tmp

  log "Installing Moonlight apt repository from vendored Cloudsmith metadata..."
  verify_file_sha256 "$VENDORED_CLOUDSMITH_SETUP_SCRIPT" "$VENDORED_CLOUDSMITH_SETUP_SHA256"
  verify_file_sha256 "$VENDORED_CLOUDSMITH_GPG_KEY" "$VENDORED_CLOUDSMITH_GPG_SHA256"

  keyring_tmp="$(mktemp)"
  source_tmp="$(mktemp)"

  if (( DRY_RUN )); then
    printf '+ gpg --dearmor --output %q %q\n' "$keyring_tmp" "$VENDORED_CLOUDSMITH_GPG_KEY"
    printf '+ sudo install -m 0644 %q %q\n' "$keyring_tmp" "$MOONLIGHT_KEYRING_PATH"
  else
    gpg --dearmor --output "$keyring_tmp" "$VENDORED_CLOUDSMITH_GPG_KEY"
    sudo_run install -m 0644 "$keyring_tmp" "$MOONLIGHT_KEYRING_PATH"
  fi

  {
    printf '# Source: Moonlight Game Streaming\n'
    printf '# Site: https://github.com/moonlight-stream/moonlight-qt\n'
    printf '# Repository: Moonlight Game Streaming / Moonlight\n'
    printf '# Description: Open-source NVIDIA GameStream client\n'
    printf '# Managed by rasberry-moonlight-client. No remote setup script is executed.\n'
    printf '\n'
    printf 'deb [signed-by=%s] %s %s main\n' "$MOONLIGHT_KEYRING_PATH" "$MOONLIGHT_REPO_BASE_URL" "$codename"
    printf 'deb-src [signed-by=%s] %s %s main\n' "$MOONLIGHT_KEYRING_PATH" "$MOONLIGHT_REPO_BASE_URL" "$codename"
  } > "$source_tmp"

  sudo_run install -m 0644 "$source_tmp" "$MOONLIGHT_SOURCE_LIST_PATH"

  rm -f "$keyring_tmp" "$source_tmp"
}

configure_user_groups() {
  log "Configuring device access groups for user '$TARGET_USER'..."
  local group
  for group in input video render audio; do
    if getent group "$group" >/dev/null 2>&1; then
      sudo_run usermod -aG "$group" "$TARGET_USER"
    else
      warn "Group '$group' does not exist; skipping."
    fi
  done
}

write_boot_config_block() {
  if (( ! CONFIGURE_BOOT )); then
    log "Skipping boot config changes because --no-boot-config is set."
    return
  fi

  if (( ! FULL_KMS && ! CONFIGURE_4K60 )); then
    return
  fi

  local boot_config
  boot_config="$(detect_boot_config)"
  if [[ -z "$boot_config" ]]; then
    warn "Could not find /boot/firmware/config.txt or /boot/config.txt; skipping boot config."
    return
  fi

  local backup="${boot_config}.moonlight-backup-$(date +%Y%m%d%H%M%S)"
  log "Updating boot config at $boot_config; backup: $backup"
  sudo_run cp "$boot_config" "$backup"

  if (( FULL_KMS )); then
    if (( DRY_RUN )); then
      printf '+ sudo sed -i -E %q %q\n' 's/^([[:space:]]*dtoverlay=vc4-fkms-v3d.*)$/# disabled by moonlight-pi-client: \1/' "$boot_config"
    else
      sudo sed -i -E 's/^([[:space:]]*dtoverlay=vc4-fkms-v3d.*)$/# disabled by moonlight-pi-client: \1/' "$boot_config"
    fi
  fi

  local block="# BEGIN moonlight-pi-client"
  block+=$'\n[all]'
  if (( FULL_KMS )); then
    block+=$'\ndtoverlay=vc4-kms-v3d'
  fi
  if (( CONFIGURE_4K60 )); then
    block+=$'\ngpu_mem=128'
  fi
  block+=$'\n# END moonlight-pi-client'

  if (( DRY_RUN )); then
    printf '+ update managed boot config block in %q\n' "$boot_config"
    printf '%s\n' "$block"
    return
  fi

  local tmp
  tmp="$(mktemp)"
  awk -v block="$block" '
    BEGIN { skip = 0; done = 0 }
    /^# BEGIN moonlight-pi-client$/ {
      if (!done) {
        print block
        done = 1
      }
      skip = 1
      next
    }
    /^# END moonlight-pi-client$/ {
      skip = 0
      next
    }
    !skip { print }
    END {
      if (!done) {
        print block
      }
    }
  ' "$boot_config" > "$tmp"

  sudo cp "$tmp" "$boot_config"
  rm -f "$tmp"
}

restore_boot_config() {
  local boot_config
  boot_config="$(detect_boot_config)"
  if [[ -z "$boot_config" ]]; then
    warn "Could not find /boot/firmware/config.txt or /boot/config.txt; skipping boot config restore."
    return
  fi

  local backup="${boot_config}.moonlight-restore-backup-$(date +%Y%m%d%H%M%S)"
  log "Removing managed Moonlight boot config from $boot_config; backup: $backup"

  if (( DRY_RUN )); then
    printf '+ sudo cp %q %q\n' "$boot_config" "$backup"
    printf '+ remove # BEGIN/# END moonlight-pi-client block from %q\n' "$boot_config"
    printf '+ re-enable lines prefixed with %q in %q\n' '# disabled by moonlight-pi-client: ' "$boot_config"
    return
  fi

  sudo cp "$boot_config" "$backup"

  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { skip = 0 }
    /^# BEGIN moonlight-pi-client$/ {
      skip = 1
      next
    }
    /^# END moonlight-pi-client$/ {
      skip = 0
      next
    }
    skip {
      next
    }
    {
      sub(/^# disabled by moonlight-pi-client: /, "", $0)
      print
    }
  ' "$boot_config" > "$tmp"

  sudo cp "$tmp" "$boot_config"
  rm -f "$tmp"
}

install_tty_launcher() {
  log "Installing /usr/local/bin/moonlight-tty..."

  local launcher_tmp env_tmp
  launcher_tmp="$(mktemp)"
  env_tmp="$(mktemp)"

  cat > "$launcher_tmp" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -r /etc/default/moonlight-tty ]]; then
  # shellcheck disable=SC1091
  . /etc/default/moonlight-tty
fi

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-eglfs}"

if [[ -n "${SDL_AUDIODRIVER:-}" ]]; then
  export SDL_AUDIODRIVER
fi

if [[ -n "${MOONLIGHT_HOST:-}" && -n "${MOONLIGHT_APP:-}" ]]; then
  exec moonlight-qt stream "$MOONLIGHT_HOST" "$MOONLIGHT_APP"
fi

exec moonlight-qt
EOF

  {
    printf '# Managed by setup-moonlight-pi.sh\n'
    printf '# Uncomment if audio needs an explicit SDL backend.\n'
    printf '# SDL_AUDIODRIVER=pulseaudio\n'
    printf 'MOONLIGHT_HOST=%q\n' "$HOST"
    printf 'MOONLIGHT_APP=%q\n' "$APP"
  } > "$env_tmp"

  sudo_run install -m 0755 "$launcher_tmp" /usr/local/bin/moonlight-tty
  sudo_run install -m 0644 "$env_tmp" /etc/default/moonlight-tty

  rm -f "$launcher_tmp" "$env_tmp"
}

select_login_profile() {
  local shell_name
  shell_name="$(detect_user_shell)"

  case "$shell_name" in
    */bash)
      if [[ -f "$TARGET_HOME/.bash_profile" ]]; then
        printf '%s\n' "$TARGET_HOME/.bash_profile"
      elif [[ -f "$TARGET_HOME/.bash_login" ]]; then
        printf '%s\n' "$TARGET_HOME/.bash_login"
      else
        printf '%s\n' "$TARGET_HOME/.profile"
      fi
      ;;
    */zsh)
      printf '%s\n' "$TARGET_HOME/.zprofile"
      ;;
    *)
      printf '%s\n' "$TARGET_HOME/.profile"
      ;;
  esac
}

configure_autostart_profile() {
  local profile target_group block tmp
  profile="$(select_login_profile)"
  target_group="$(id -gn "$TARGET_USER")"

  log "Adding TTY1 autostart block to $profile..."

  block='# BEGIN moonlight-pi-client-autostart'
  block+=$'\nif [ "$(tty)" = "/dev/tty1" ] && [ -z "${SSH_CONNECTION:-}" ] && command -v moonlight-tty >/dev/null 2>&1; then'
  block+=$'\n  sleep 5'
  block+=$'\n  exec moonlight-tty'
  block+=$'\nfi'
  block+=$'\n# END moonlight-pi-client-autostart'

  if (( DRY_RUN )); then
    printf '+ update managed autostart block in %q for user %q\n' "$profile" "$TARGET_USER"
    printf '%s\n' "$block"
    return
  fi

  sudo mkdir -p "$(dirname "$profile")"
  sudo touch "$profile"
  sudo chown "$TARGET_USER:$target_group" "$profile"

  tmp="$(mktemp)"
  awk -v block="$block" '
    BEGIN { skip = 0; done = 0 }
    /^# BEGIN moonlight-pi-client-autostart$/ {
      if (!done) {
        print block
        done = 1
      }
      skip = 1
      next
    }
    /^# END moonlight-pi-client-autostart$/ {
      skip = 0
      next
    }
    !skip { print }
    END {
      if (!done) {
        print block
      }
    }
  ' "$profile" > "$tmp"

  sudo install -o "$TARGET_USER" -g "$target_group" -m 0644 "$tmp" "$profile"
  rm -f "$tmp"
}

remove_autostart_profile() {
  local profile target_group tmp
  profile="$(select_login_profile)"

  if [[ ! -e "$profile" ]]; then
    log "No login profile found at $profile; nothing to remove."
    return
  fi

  target_group="$(id -gn "$TARGET_USER")"
  log "Removing managed TTY1 autostart block from $profile..."

  if (( DRY_RUN )); then
    printf '+ remove # BEGIN/# END moonlight-pi-client-autostart block from %q\n' "$profile"
    return
  fi

  tmp="$(mktemp)"
  awk '
    BEGIN { skip = 0 }
    /^# BEGIN moonlight-pi-client-autostart$/ {
      skip = 1
      next
    }
    /^# END moonlight-pi-client-autostart$/ {
      skip = 0
      next
    }
    !skip { print }
  ' "$profile" > "$tmp"

  sudo install -o "$TARGET_USER" -g "$target_group" -m 0644 "$tmp" "$profile"
  rm -f "$tmp"
}

configure_console_autologin() {
  if (( ! CONFIGURE_AUTOLOGIN )); then
    log "Skipping raspi-config boot behavior changes because --no-autologin is set."
    return
  fi

  if ! command -v raspi-config >/dev/null 2>&1; then
    warn "raspi-config not found; set Console Autologin manually if you want TTY autostart."
    return
  fi

  log "Configuring Console Autologin with raspi-config..."
  if (( EUID == 0 )); then
    run env SUDO_USER="$TARGET_USER" raspi-config nonint do_boot_behaviour B2
  else
    run sudo env SUDO_USER="$TARGET_USER" raspi-config nonint do_boot_behaviour B2
  fi
}

print_restore_next_steps() {
  cat <<'EOF'

[moonlight-pi] Restore action complete.

Next steps:
  1. Reboot if boot config or login profile changes should take effect immediately.
  2. If the Pi still boots to console and you want desktop boot, run:
       sudo raspi-config
     Then choose System Options -> Boot / Auto Login -> Desktop Autologin.
EOF
}

install_virtualhere() {
  local binary_name service_tmp

  [[ -f "$VIRTUALHERE_BINARY" ]] || die "VirtualHere binary was not found: $VIRTUALHERE_BINARY"

  binary_name="$(basename "$VIRTUALHERE_BINARY")"
  service_tmp="$(mktemp)"

  log "Installing local VirtualHere server binary: $VIRTUALHERE_BINARY"

  if (( DRY_RUN )); then
    printf '+ sudo install -m 0755 %q %q\n' "$VIRTUALHERE_BINARY" "/usr/local/sbin/$binary_name"
    printf '+ sudo mkdir -p /usr/local/etc/virtualhere\n'
    printf '+ sudo install -m 0644 <generated service> /etc/systemd/system/virtualhere.service\n'
    printf '+ sudo systemctl daemon-reload\n'
    printf '+ sudo systemctl enable virtualhere.service\n'
    printf '+ sudo systemctl start virtualhere.service\n'
    rm -f "$service_tmp"
    return
  fi

  sudo_run install -m 0755 "$VIRTUALHERE_BINARY" "/usr/local/sbin/$binary_name"
  sudo_run mkdir -p /usr/local/etc/virtualhere

  cat > "$service_tmp" <<EOF
[Unit]
Description=VirtualHere Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/sbin/$binary_name -b -c /usr/local/etc/virtualhere/config.ini

[Install]
WantedBy=multi-user.target
EOF

  sudo_run install -m 0644 "$service_tmp" /etc/systemd/system/virtualhere.service
  sudo_run systemctl daemon-reload
  sudo_run systemctl enable virtualhere.service
  sudo_run systemctl start virtualhere.service

  rm -f "$service_tmp"
}

print_next_steps() {
  cat <<EOF

[moonlight-pi] Done.

Next steps:
  1. Reboot before testing group, boot config, and autostart changes.
  2. Pair your host from the Pi:
       moonlight-qt pair <HOST_IP>
  3. Recommended first settings: 1080p, 60 FPS, HEVC/H.265, Force Hardware Decoding, about 40 Mbps.
EOF

  if [[ -n "$HOST" && -n "$APP" ]]; then
    cat <<EOF
  4. This setup will auto-stream after reboot:
       moonlight-qt stream $HOST "$APP"
EOF
  fi

  if (( AUTOSTART )); then
    cat <<'EOF'
  5. TTY1 autostart is enabled. To return to desktop boot, run:
       sudo raspi-config
EOF
  fi

  if (( LITE_AUDIO )); then
    cat <<'EOF'
  6. For Raspberry Pi OS Lite audio, run:
       sudo raspi-config
     Then select PulseAudio and your HDMI/analog/USB output.
EOF
  fi
}

main() {
  parse_args "$@"

  TARGET_USER="$(detect_target_user)"
  id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' does not exist"
  TARGET_HOME="$(detect_user_home)"
  [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || die "Home directory for '$TARGET_USER' was not found"

  if (( REMOVE_AUTOSTART || RESTORE_BOOT_CONFIG )); then
    if (( REMOVE_AUTOSTART )); then
      remove_autostart_profile
    fi

    if (( RESTORE_BOOT_CONFIG )); then
      restore_boot_config
    fi

    print_restore_next_steps

    if (( REBOOT )); then
      log "Rebooting..."
      sudo_run reboot
    fi

    exit 0
  fi

  print_environment_note
  install_moonlight
  if (( CONFIGURE_GROUPS )); then
    configure_user_groups
  else
    log "Skipping user group changes because --no-groups is set."
  fi
  write_boot_config_block
  install_tty_launcher

  if (( AUTOSTART )); then
    configure_autostart_profile
    configure_console_autologin
  fi

  if (( INSTALL_VIRTUALHERE )); then
    install_virtualhere
  fi

  print_next_steps

  if (( REBOOT )); then
    log "Rebooting..."
    sudo_run reboot
  fi
}

main "$@"
