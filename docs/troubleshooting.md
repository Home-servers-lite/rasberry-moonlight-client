# Troubleshooting

This page covers the common Raspberry Pi Moonlight issues that are worth checking before changing advanced settings.

## First Baseline Test

Start with a simple known-good baseline:

- Raspberry Pi and host PC on the same LAN
- Ethernet on the host PC
- Ethernet on the Pi if possible
- Moonlight launched from a TTY, not from the desktop
- 1080p, 60 FPS, HEVC/H.265, Force Hardware Decoding, around 40 Mbps

If that works, raise resolution, bitrate, or optional features one at a time.

## No Audio

On Raspberry Pi OS Lite, install PulseAudio:

```bash
bash scripts/setup-moonlight-pi.sh --lite-audio
sudo reboot
```

Then choose the output in `raspi-config`:

```bash
sudo raspi-config
```

Look for the audio options under Advanced Settings or System Settings, depending on your Raspberry Pi OS version.

If audio still does not work, test explicit SDL audio drivers:

```bash
SDL_AUDIODRIVER=alsa moonlight-qt
SDL_AUDIODRIVER=pulseaudio moonlight-qt
```

For TTY auto-start, set the driver in:

```bash
sudo nano /etc/default/moonlight-tty
```

Example:

```bash
SDL_AUDIODRIVER=pulseaudio
```

## HDR Is Missing

HDR generally requires Moonlight to run from a console/TTY. It is commonly unavailable from the desktop environment.

Check that the Pi is using Full KMS:

```bash
grep -n "vc4-.*kms-v3d" /boot/firmware/config.txt /boot/config.txt 2>/dev/null
```

The expected modern setting is:

```bash
dtoverlay=vc4-kms-v3d
```

Avoid the older `vc4-fkms-v3d` overlay for Bookworm and newer.

## Controller Features Do Not Work

Make sure the user running Moonlight has input permissions:

```bash
sudo usermod -aG input $USER
sudo reboot
```

The setup script also adds the user to `video`, `render`, and `audio` groups when those groups exist:

```bash
bash scripts/setup-moonlight-pi.sh --no-boot-config --no-autologin
sudo reboot
```

Use `--virtualhere --virtualhere-binary PATH` if you want USB devices on the Pi to appear as if they are connected directly to the gaming PC. The script does not download VirtualHere automatically; provide a local server binary that you have reviewed or obtained separately.

## Black Screen Or Slow Stream Start

Try these in order:

- launch Moonlight from TTY1 with `moonlight-tty`
- lower the stream to 1080p/60
- use HEVC/H.265 with Force Hardware Decoding
- use Ethernet for the Pi and host PC
- reboot after boot config or group changes
- test another HDMI cable or display mode if using 4K

If the problem only happens at 4K/60:

```bash
bash scripts/setup-moonlight-pi.sh --4k60
sudo reboot
```

## High Latency Or Stutter

Use the performance baseline first:

- 1080p
- 60 FPS
- 40 Mbps
- HEVC/H.265
- Force Hardware Decoding
- TTY launch

Then check the network. The host PC should be wired. Wi-Fi can work for the Pi, but weak 5 GHz signal, 2.4 GHz Wi-Fi, or powerline adapters can add jitter.

On a Pi 4, avoid running Moonlight inside a 4K desktop session. If you need the desktop, keep the display resolution at 1080p or below.

## TTY Auto-Start Opens The UI Instead Of A Game

Direct stream requires both host and app values:

```bash
bash scripts/setup-moonlight-pi.sh --autostart --host 192.168.1.50 --app "Desktop"
moonlight-qt pair 192.168.1.50
sudo reboot
```

If only `--autostart` is set, the launcher opens the Moonlight UI.

You can edit the values later:

```bash
sudo nano /etc/default/moonlight-tty
```

## Remove TTY Auto-Start

Remove only the managed login profile block:

```bash
bash scripts/setup-moonlight-pi.sh --remove-autostart
sudo reboot
```

If the Pi still boots to console and you want desktop boot:

```bash
sudo raspi-config
```

Then choose System Options -> Boot / Auto Login -> Desktop Autologin.

## Restore Boot Config Changes

Remove the managed boot config block and re-enable any lines that the script commented with its own marker:

```bash
bash scripts/setup-moonlight-pi.sh --restore-boot-config
sudo reboot
```

The restore action creates a timestamped backup before editing the boot config.

## Dry Run

Use `--dry-run` before making system changes:

```bash
bash scripts/setup-moonlight-pi.sh --dry-run --autostart --lite-audio --4k60
```

For a minimal install without boot config, group, or autologin changes:

```bash
bash scripts/setup-moonlight-pi.sh --no-boot-config --no-groups --no-autologin
```
