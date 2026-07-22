# Raspberry Pi Moonlight Client

Turn a Raspberry Pi 4 or Raspberry Pi 5 into a dedicated Moonlight Qt client for low-latency game streaming from a gaming PC. The setup focuses on the practical pieces that matter for a living-room or portable LAN streaming box: official Moonlight installation, TTY launch for better performance, optional auto-start on boot, audio support for Raspberry Pi OS Lite, controller/device permissions, optional 4K/60 decoder tuning, and optional USB-over-IP through VirtualHere.

The default path targets Raspberry Pi OS 12 Bookworm or newer. It uses the official Moonlight Cloudsmith apt repository, keeps Full KMS enabled with `vc4-kms-v3d`, and avoids older Bullseye-era boot overlay tweaks such as `vc4-fkms-v3d` and `rpivid-v4l2`.

## Quick Start

On the Raspberry Pi:

```bash
git clone https://github.com/Home-servers-lite/rasberry-moonlight-client.git
cd rasberry-moonlight-client
bash scripts/setup-moonlight-pi.sh --autostart --lite-audio --4k60
sudo reboot
```

One-line checkout and install from this repo:

```bash
git clone https://github.com/Home-servers-lite/rasberry-moonlight-client.git && cd rasberry-moonlight-client && bash scripts/setup-moonlight-pi.sh --autostart --lite-audio --4k60
```

Minimal install without auto-start:

```bash
bash scripts/setup-moonlight-pi.sh
moonlight-qt
```

Safer install that avoids boot config, group, and autologin changes:

```bash
bash scripts/setup-moonlight-pi.sh --no-boot-config --no-groups --no-autologin
```

Auto-start a specific host/app:

```bash
bash scripts/setup-moonlight-pi.sh --autostart --host 192.168.1.50 --app "Desktop"
moonlight-qt pair 192.168.1.50
sudo reboot
```

Install VirtualHere for USB-over-IP from a local VirtualHere server binary, for example for a Bluetooth dongle or wired DualSense connected through the gaming PC:

```bash
bash scripts/setup-moonlight-pi.sh --autostart --virtualhere --virtualhere-binary ./vhusbdarm64
```

## What The Script Does

- installs `moonlight-qt` from the official Moonlight Cloudsmith apt repository
- configures the Moonlight apt repository from vendored Cloudsmith metadata instead of running a remote setup script
- runs `apt update` and, by default, `apt upgrade`
- adds the selected user to `input`, `video`, `render`, and `audio` if those groups exist
- creates `/usr/local/bin/moonlight-tty`, which launches Moonlight in a TTY with `QT_QPA_PLATFORM=eglfs`
- optionally configures TTY1 auto-start and Console Autologin through `raspi-config`
- optionally installs `pulseaudio` for Raspberry Pi OS Lite
- optionally adds `gpu_mem=128` for 4K/60 decoder issues
- keeps boot config changes in a managed block and creates a backup before editing
- can remove its managed TTY auto-start and boot config changes
- optionally installs VirtualHere server from a local binary path

The installer does not execute the Cloudsmith `setup.deb.sh` script at runtime. A copy is stored in [vendor/cloudsmith/setup.deb.sh](vendor/cloudsmith/setup.deb.sh) for audit/provenance, and the installer writes the apt source file itself using the vendored GPG key in [vendor/cloudsmith/gpg.2F6AE14E1C660D44.key](vendor/cloudsmith/gpg.2F6AE14E1C660D44.key).

## Recommended Moonlight Settings

Open `moonlight-qt`, go to settings, and start with:

- Resolution: `1080p`
- FPS: `60`
- Bitrate: around `40 Mbps` for a stable LAN baseline
- Video decoder: `Force Hardware Decoding`
- Video codec: `HEVC (H.265)`
- V-Sync: `On`

The Pi 4 is most reliable at 1080p/60. The Pi 5 can go further, but 4K/60 depends on the host, display, HDMI cable, power supply, codec, and current Raspberry Pi OS/Moonlight packages. 4K/120 is not a realistic target for a Raspberry Pi client.

## Host PC Checklist

Your gaming PC needs Sunshine or a GeForce Experience/GameStream-compatible host.

Sunshine is the recommended path for new setups:

1. Install Sunshine on the gaming PC.
2. Open the Sunshine web UI and create an admin account.
3. Make sure the Pi and gaming PC are on the same LAN.
4. Start `moonlight-qt` on the Pi and pair the host.
5. Test `Desktop`, `Steam Big Picture`, or a specific game.

For the lowest latency:

- use Ethernet for the host PC
- use Ethernet for the Pi if possible
- if the Pi uses Wi-Fi, use a strong 5 GHz signal
- launch Moonlight from a TTY instead of a desktop session

## TTY Auto-Start

With `--autostart`, the script:

- sets the Pi to boot into Console Autologin
- adds a managed block to the selected user's login profile
- starts `moonlight-tty` only on `/dev/tty1`

Useful shortcuts:

- TTY1: `Ctrl+Alt+F1`
- other TTYs: `Ctrl+Alt+F2` to `Ctrl+Alt+F6`
- desktop session, if running: often `Ctrl+Alt+F7`

To return to desktop boot:

```bash
sudo raspi-config
```

Then choose System Options -> Boot / Auto Login -> Desktop Autologin.

To start the desktop manually from a TTY:

```bash
sudo systemctl start lightdm
```

## Audio On Raspberry Pi OS Lite

If you use a Lite image, run the script with:

```bash
bash scripts/setup-moonlight-pi.sh --lite-audio
```

Then choose the audio output:

```bash
sudo raspi-config
```

The menu path is usually Advanced Settings -> Audio Config for PulseAudio, then System Settings -> Audio for HDMI/analog/USB output.

If Moonlight has no sound, try:

```bash
SDL_AUDIODRIVER=alsa moonlight-qt
SDL_AUDIODRIVER=pulseaudio moonlight-qt
```

For the TTY launcher, you can set the driver in:

```bash
sudo nano /etc/default/moonlight-tty
```

Example:

```bash
SDL_AUDIODRIVER=pulseaudio
```

## Pairing And Direct Streaming

Pair:

```bash
moonlight-qt pair 192.168.1.50
```

Stream to an app:

```bash
moonlight-qt stream 192.168.1.50 "Desktop"
```

If you set `--host` and `--app`, auto-start uses those values. If they are not set, auto-start opens the Moonlight UI.

## VirtualHere

VirtualHere forwards USB devices from the Pi to the host PC. This is useful for:

- a USB Bluetooth dongle that Windows/Linux/macOS sees as locally connected to the host
- DualSense/DualShock over USB with more controller features
- other single USB devices

Without a paid license, VirtualHere server allows one USB device at a time. A Bluetooth dongle can still serve multiple Bluetooth controllers because the forwarded USB device is the dongle itself.

Windows usually does not handle two active Bluetooth adapters well. If you forward a USB Bluetooth dongle from the Pi, disable or unplug the host Bluetooth adapter if there is a conflict.

## Script Options

```bash
bash scripts/setup-moonlight-pi.sh --help
```

Main options:

- `--autostart`: Console Autologin plus Moonlight auto-start on TTY1
- `--host IP_OR_HOSTNAME`: host for direct streaming
- `--app APP_NAME`: app for direct streaming, for example `"Desktop"`
- `--virtualhere`: installs VirtualHere server from a local binary
- `--virtualhere-binary PATH`: local VirtualHere server binary to install
- `--lite-audio`: installs PulseAudio for Raspberry Pi OS Lite
- `--4k60`: adds `gpu_mem=128` to boot config
- `--no-boot-config`: does not edit `/boot/firmware/config.txt` or `/boot/config.txt`
- `--no-groups`: does not add the user to device access groups
- `--no-autologin`: does not change boot behavior with `raspi-config`
- `--remove-autostart`: removes the managed TTY1 auto-start block
- `--restore-boot-config`: removes the managed boot config block
- `--skip-upgrade`: skips `apt upgrade`
- `--skip-kms`: does not touch KMS boot config
- `--user USER`: selects which user gets autostart/group changes
- `--dry-run`: prints what the script would do

## Restore And Cleanup

Remove TTY auto-start without reinstalling Moonlight:

```bash
bash scripts/setup-moonlight-pi.sh --remove-autostart
sudo reboot
```

Remove the managed boot config block and re-enable lines that the script commented with its own marker:

```bash
bash scripts/setup-moonlight-pi.sh --restore-boot-config
sudo reboot
```

These commands do not uninstall `moonlight-qt` or VirtualHere. They only undo the managed changes made by this setup script.

## Troubleshooting

More detail is available in [docs/troubleshooting.md](docs/troubleshooting.md).

HDR cannot be enabled:

- launch Moonlight from a TTY, not from the desktop
- make sure boot config uses `dtoverlay=vc4-kms-v3d`, not `vc4-fkms-v3d`

Controller features do not work:

```bash
sudo usermod -aG input $USER
sudo reboot
```

4K/60 decoder errors:

```bash
bash scripts/setup-moonlight-pi.sh --4k60
sudo reboot
```

Latency or stutter:

- test 1080p/60, HEVC, 40 Mbps first
- use Ethernet for at least the gaming PC
- launch from a TTY
- do not run the Moonlight window inside a 4K desktop session on a Pi 4

## References

- https://github.com/moonlight-stream/moonlight-docs/wiki/Installing-Moonlight-Qt-on-Raspberry-Pi-4
- https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- https://www.reddit.com/r/MoonlightStreaming/comments/1ju40yv/the_perfect_moonlight_setup_on_raspberry_pi/
- https://www.reddit.com/r/raspberry_pi/comments/rn4bkz/raspberry_pi_4_moonlight_game_streaming_howto/

## License

MIT. See [LICENSE](LICENSE).
