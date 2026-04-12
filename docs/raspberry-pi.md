# Raspberry Pi Setup Guide

The Raspberry Pi is the canonical UDP Blaster sender — small, headless, runs 24/7, and plugs into a Razer Ripsaw HD over USB 3.0. This guide walks through a fresh Pi from blank SD card to streaming.

```
[HDMI source] → [Ripsaw HD] → [Raspberry Pi] ── UDP/network ──→ [Receiver + OBS]
                                  ffmpeg
```

> The examples use `mypi` as the hostname. Substitute whatever you set in the imager. The Makefile defaults `PI_HOSTNAME=churchpi` (the original use case) — override with `make ssh-pi PI_HOSTNAME=mypi` or set it in `.config.mk`.

---

## Step 1: Flash the SD card with Raspberry Pi Imager

Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on your computer.

**Linux (Flatpak):**
```bash
flatpak install flathub org.raspberrypi.rpi-imager
flatpak run org.raspberrypi.rpi-imager
```

**macOS:**
```bash
brew install --cask raspberry-pi-imager
```

### 1.1 Choose Device, OS, Storage
- Device: your Pi model (Pi 4, Pi 5, etc.)
- OS: **Raspberry Pi OS (64-bit)** for Pi 4/5; 32-bit for older models
- Storage: insert your microSD card (16 GB+ recommended)

### 1.2 Configure Settings (IMPORTANT)

Before clicking **Next**, hit the **gear icon** (⚙) or `Ctrl+Shift+X` to open advanced settings:

| Setting | Value | Notes |
|---|---|---|
| **Set hostname** | `mypi` | Used to find the Pi on the network via mDNS |
| **Enable SSH** | ✅ password authentication | Required for remote access |
| **Set username** | `pi` (or your choice) | Remember this |
| **Set password** | (your choice) | Use something secure |
| **Configure WiFi** | ✅ | See below |
| **WiFi SSID** | Your network's SSID | Case-sensitive |
| **WiFi password** | Your network's password | |
| **WiFi country** | `US` | Or your country code |
| **Set locale** | ✅ | |
| **Timezone** | `America/Chicago` | Or your timezone |
| **Keyboard layout** | `us` | Or your layout |

### 1.3 Write the image
- Click **Save**, then **Next** → **Yes** to write
- ~5–10 minutes for write + verification
- Eject the SD card safely

---

## Step 2: First boot

1. Insert the SD card into the Pi.
2. (Optional) Connect ethernet — usually faster and more reliable than WiFi for first boot.
3. Connect power.
4. Wait 1–2 minutes for first boot to provision itself.

---

## Step 3: Find the Pi on the network

**Option A — mDNS (usually works):**
```bash
ping mypi.local
```

**Option B — let the Makefile find it:**
```bash
make find-pi PI_HOSTNAME=mypi
```
This tries mDNS first, then falls back to an `nmap` scan if mDNS fails.

**Option C — direct ethernet:** plug the Pi straight into your laptop with an ethernet cable. It will be reachable at `mypi.local` (or `raspberrypi.local`).

---

## Step 4: SSH in

```bash
ssh pi@mypi.local
```
Enter the password you set in the imager. If you get a host key warning, type `yes`.

---

## Step 5: Install dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ffmpeg v4l-utils alsa-utils git make
sudo reboot
```

Wait 30 seconds, then reconnect:
```bash
ssh pi@mypi.local
```

---

## Step 6: Get UDP Blaster onto the Pi

**Option A — clone from git:**
```bash
git clone https://github.com/nathandrew/udp-blaster.git
cd udp-blaster
```

**Option B — copy from your laptop:**
```bash
# from your laptop, not the Pi
scp -r /path/to/udp-blaster pi@mypi.local:~/
```

---

## Step 7: Connect the Razer Ripsaw HD

1. Plug the Ripsaw into a **USB 3.0** port (the blue ones).
2. Connect your camera/HDMI source to the Ripsaw's HDMI input.
3. Power on the source so the Ripsaw has signal to negotiate.
4. Detect the device:

```bash
cd ~/udp-blaster
make detect
```

You should see something like:
```
Razer Ripsaw HD:
    /dev/video0

card 2: Ripsaw [Razer Ripsaw HD], device 0
```

---

## Step 8: Save your config

```bash
make setup
```

Pick the Ripsaw video device, the Ripsaw audio card, and enter the IP of the receiver machine running OBS. The picker writes to `.config.mk`, so future `make stream` calls don't need any arguments.

---

## Step 9: Test capture

```bash
make test-video    # opens an ffplay preview (needs X forwarding for headless)
make test-audio    # shows audio level meter
```

Headless tip: skip `make test-video` on the Pi itself and just use `make stream` + a `make test-receive` (VLC) on your laptop to verify the pipeline.

---

## Step 10: Stream

```bash
make stream
```

(Or override the receiver IP inline: `make stream TARGET_IP=192.168.1.100`.)

On your receiver machine, configure OBS to listen — see [`streaming.md`](streaming.md#5-start-streaming) for the Media Source settings, or just run `make test-receive` to verify the stream is reaching your laptop with VLC first.

`Ctrl+C` to stop.

---

## Quick reference

| Task | Command |
|---|---|
| SSH to Pi | `ssh pi@mypi.local` (or `make ssh-pi`) |
| Find Pi | `make find-pi PI_HOSTNAME=mypi` |
| Detect devices | `make detect` |
| Test video | `make test-video` |
| Test audio | `make test-audio` |
| Save config | `make setup` |
| Start stream | `make stream` |
| Override target | `make stream TARGET_IP=<ip>` |
| Stop stream | `Ctrl+C` (or `make stop`) |
| Pi IP from Pi | `hostname -I` |
| Reboot Pi | `sudo reboot` |
| Shutdown Pi | `sudo shutdown now` |

---

## Performance notes

| Model | RAM | Realistic ceiling | Notes |
|---|---|---|---|
| **Pi 5** | 4 / 8 GB | 1080p60 | Best performance, handles high bitrates easily |
| **Pi 4** | 4 GB+ | 1080p30 | Recommended minimum for full HD |
| **Pi 4** | 2 GB | 720p30 | Works but limited headroom |
| **Pi 3** | 1 GB | 720p30 | Usable but may drop frames |
| **Pi Zero** | — | — | Not recommended for h.264 encoding |

**Pi 5 specifics:**
- USB-C power, 5V/5A recommended for full performance
- Two USB 3.0 ports (blue) — use these for the Ripsaw
- Comfortable at 1080p60 with higher bitrates:
  ```bash
  make stream RESOLUTION=1920x1080 FRAMERATE=60 VIDEO_BITRATE=8000k
  ```
- Active cooling recommended for sustained streaming

**Pi 4:**
```bash
make stream                                      # 1080p30 default
make stream RESOLUTION=1280x720 VIDEO_BITRATE=2500k   # if dropping frames
```

**Pi 3:**
```bash
make stream RESOLUTION=1280x720 VIDEO_BITRATE=2000k FRAMERATE=24
```

---

## Alternative: manual SD card setup

If you already have an OS image and need to configure it manually instead of using the imager UI:

**Enable SSH** — create an empty file on the boot partition:
```bash
touch /path/to/boot/ssh
```

**Configure WiFi** — create `wpa_supplicant.conf` on the boot partition:
```bash
cat > /path/to/boot/wpa_supplicant.conf << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="YourNetworkName"
    psk="YourPassword"
    key_mgmt=WPA-PSK
}
EOF
```

Then boot the Pi normally and SSH in.

---

## Auto-start streaming on boot (optional)

To make the Pi start streaming whenever it powers on, create a systemd unit:

```bash
sudo tee /etc/systemd/system/udp-blaster.service > /dev/null <<EOF
[Unit]
Description=UDP Blaster
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/udp-blaster
ExecStart=/usr/bin/make stream
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now udp-blaster.service
```

Check status:
```bash
systemctl status udp-blaster.service
journalctl -u udp-blaster.service -f
```

> Make sure `.config.mk` exists with your `TARGET_IP` set before enabling the service, otherwise it'll stream to the default IP (`192.168.1.100`) and the receiver won't get anything.
