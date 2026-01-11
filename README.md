# Church Video Streaming Setup

Stream video/audio from Razer Ripsaw HD to another device running OBS.

## Architecture

```
[Camera/Source] → [Ripsaw HD] → [This Linux PC] → [Network] → [OBS PC] → [Zoom]
                                    ffmpeg           UDP/RTMP     OBS
```

## Quick Start

```bash
# 1. Detect your devices
make detect

# 2. Edit Makefile with correct device paths (VIDEO_DEV, AUDIO_DEV)

# 3. Test locally
make test-video

# 4. Stream to OBS machine
make stream-udp TARGET_IP=192.168.1.100
```

## Technology Overview

### FFmpeg
Command-line tool that captures video/audio from devices and encodes/transmits it. We use it to grab frames from the Ripsaw HD and send them over the network.

### V4L2 (Video4Linux2)
Linux kernel interface for video capture devices. Your Ripsaw HD appears as `/dev/videoX`. FFmpeg reads from this device.

### ALSA
Linux audio system. The Ripsaw HD's audio appears as a capture device like `hw:2,0`. FFmpeg captures audio through ALSA.

### UDP vs RTMP

| Feature | UDP | RTMP |
|---------|-----|------|
| Latency | ~0.5-1 sec | ~2-5 sec |
| Reliability | May drop packets | Reliable delivery |
| Setup | Simple - direct connection | Needs RTMP server |
| Best for | Same network, low latency | Unstable networks |

**Recommendation**: Use UDP for same-network streaming (simpler, lower latency).

### Encoding Settings

- **libx264**: H.264 video encoder (widely compatible)
- **preset ultrafast**: Minimal CPU usage, some quality tradeoff
- **tune zerolatency**: Removes buffering for live streaming
- **aac**: Audio codec (compatible with everything)

## OBS Setup (Receiving Machine)

### For UDP Stream

1. Add Source → **Media Source**
2. Uncheck "Local File"
3. Input: `udp://@:5000`
4. Check "Restart playback when source becomes active"

### For RTMP Stream

First, install an RTMP server on the OBS machine:

**Windows**: Use [nginx-rtmp-win32](https://github.com/nicedaysola/nginx-rtmp-win32/releases)

**Linux/Mac**:
```bash
# Using Docker (easiest)
docker run -p 1935:1935 tiangolo/nginx-rtmp
```

Then in OBS:
1. Add Source → **Media Source**
2. Uncheck "Local File"
3. Input: `rtmp://localhost/live/stream`

## Finding Your Devices

Run `make detect` to list devices. Look for "Ripsaw" in the output.

**Video device example output**:
```
Razer Ripsaw HD (usb-0000:00:14.0-1):
        /dev/video0
        /dev/video1
```
Use the first one (without "1" suffix): `VIDEO_DEV=/dev/video0`

**Audio device example output**:
```
card 2: Ripsaw [Razer Ripsaw HD], device 0: USB Audio [USB Audio]
```
Format as `hw:CARD,DEVICE`: `AUDIO_DEV=hw:2,0`

## Troubleshooting

### "Device or resource busy"
Another program is using the capture card. Close OBS/VLC on this machine.

### No video/black screen
- Check `make detect` - device might be different path
- Try `make test-video` first
- Some capture cards need input signal before they work

### No audio
- Run `make test-audio` to verify levels
- Check `arecord -l` for correct device number
- Ensure audio is coming through the HDMI/source

### High latency
- Use UDP instead of RTMP
- Lower resolution: `make stream-udp RESOLUTION=1280x720`
- Ensure both machines are on same network (not through internet)

### Choppy video
- Reduce bitrate: `make stream-udp VIDEO_BITRATE=3000k`
- Lower framerate: `make stream-udp FRAMERATE=24`

## Raspberry Pi Setup Guide

Complete guide for setting up a headless Raspberry Pi (no monitor needed) for church video streaming.

---

### Step 1: Raspberry Pi Imager Settings

Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/) on your computer.

**Linux (Flatpak):**
```bash
flatpak install flathub org.raspberrypi.rpi-imager
flatpak run org.raspberrypi.rpi-imager
```

**1.1 Choose Device**
- Click "Choose Device"
- Select your Pi model (e.g., Raspberry Pi 4, Raspberry Pi 5)

**1.2 Choose OS**
- Click "Choose OS"
- Select **Raspberry Pi OS (64-bit)** - recommended for Pi 4/5
- Or **Raspberry Pi OS (32-bit)** for older Pi models

**1.3 Choose Storage**
- Insert your microSD card (16GB+ recommended)
- Click "Choose Storage" and select your SD card

**1.4 Configure Settings (IMPORTANT)**

Before clicking "Next", click the **gear icon** (⚙️) or press **Ctrl+Shift+X** to open advanced settings:

| Setting | Value | Notes |
|---------|-------|-------|
| **Set hostname** | `churchpi` | Used to find Pi on network |
| **Enable SSH** | ✅ Use password authentication | Required for remote access |
| **Set username** | `pi` (or your choice) | Remember this! |
| **Set password** | (your choice) | Use something secure |
| **Configure WiFi** | ✅ | See below |
| **WiFi SSID** | Your church's WiFi name | Case-sensitive |
| **WiFi Password** | Your church's WiFi password | |
| **WiFi Country** | `US` | Or your country code |
| **Set locale** | ✅ | |
| **Timezone** | `America/Chicago` | Or your timezone |
| **Keyboard layout** | `us` | Or your layout |

**1.5 Write the Image**
- Click "Save" to save settings
- Click "Next" then "Yes" to write
- Wait for write + verification to complete (~5-10 minutes)
- Eject the SD card safely

---

### Step 2: Plug In and Power On

**What you need:**
- Raspberry Pi with the configured SD card inserted
- Power supply (USB-C for Pi 4/5, micro-USB for older)
- Ethernet cable (optional but recommended for initial setup)
- Razer Ripsaw HD (connect after initial setup)

**2.1 Initial Boot**
1. Insert the SD card into the Pi
2. (Optional) Connect ethernet cable to Pi and your router
3. Connect the power supply
4. Wait 1-2 minutes for first boot (the Pi configures itself)

**2.2 Find Your Pi on the Network**

**Option A - Hostname (usually works):**
```bash
ping churchpi.local
```
If it responds, you're ready to connect.

**Option B - Network scan (if hostname doesn't work):**
```bash
# Linux/Mac
nmap -sn 192.168.1.0/24 | grep -B2 -i "raspberry\|pi"

# Or check your router's admin page for connected devices
# Look for "churchpi" or "raspberrypi"
```

**Option C - Direct ethernet (no WiFi needed):**
Connect Pi directly to your laptop with ethernet. It will be at:
```
raspberrypi.local or churchpi.local
```

---

### Step 3: First SSH Connection

```bash
ssh pi@churchpi.local
# Enter the password you set in Imager
```

If you get a host key warning, type `yes` to continue.

---

### Step 4: Initial System Setup

Run these commands after connecting:

```bash
# Update the system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y ffmpeg v4l-utils alsa-utils git make

# Reboot to apply updates
sudo reboot
```

Wait 30 seconds, then reconnect:
```bash
ssh pi@churchpi.local
```

---

### Step 5: Get the Streaming Software

**Option A - Clone from Git:**
```bash
git clone https://github.com/YOUR_USERNAME/church-video.git
cd church-video
```

**Option B - Copy from your computer:**
```bash
# Run this FROM your laptop (not the Pi)
scp -r /path/to/church-video pi@churchpi.local:~/
```

---

### Step 6: Connect and Configure Ripsaw HD

1. Plug the Razer Ripsaw HD into a USB 3.0 port (blue port)
2. Connect your camera/video source to the Ripsaw's HDMI input
3. Detect the devices:

```bash
cd ~/church-video
make detect
```

Look for output like:
```
Razer Ripsaw HD:
    /dev/video0

Audio device:
    card 2: Ripsaw [Razer Ripsaw HD], device 0
```

4. Update the Makefile if needed:
```bash
nano Makefile
# Set VIDEO_DEV=/dev/video0 (or whatever was detected)
# Set AUDIO_DEV=hw:2,0 (format: hw:CARD,DEVICE)
```

---

### Step 7: Test the Setup

```bash
# Test video capture (will show info, not actual video)
make test-video

# Test audio levels
make test-audio
```

---

### Step 8: Start Streaming

Find the IP address of the computer running OBS:
```bash
# On the OBS computer, run:
# Windows: ipconfig
# Linux/Mac: ip addr or ifconfig
```

Start the stream from the Pi:
```bash
make stream-udp TARGET_IP=192.168.1.100
# Replace with your OBS computer's IP
```

See the "OBS Setup" section above for configuring OBS to receive the stream.

---

### Quick Reference Card

| Task | Command |
|------|---------|
| SSH to Pi | `ssh pi@churchpi.local` |
| Detect devices | `make detect` |
| Test video | `make test-video` |
| Test audio | `make test-audio` |
| Start UDP stream | `make stream-udp TARGET_IP=<ip>` |
| Stop stream | `Ctrl+C` |
| Check Pi IP | `hostname -I` |
| Reboot Pi | `sudo reboot` |
| Shutdown Pi safely | `sudo shutdown now` |

---

### Alternative: Manual SD Card Setup

If you already have an OS image and need to configure it manually:

**Enable SSH** - create empty file on boot partition:
```bash
touch /path/to/boot/ssh
```

**Configure WiFi** - create `wpa_supplicant.conf` on boot partition:
```bash
cat > /path/to/boot/wpa_supplicant.conf << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="ChurchWiFiName"
    psk="WiFiPassword"
    key_mgmt=WPA-PSK
}
EOF
```

## Dependencies

**Arch Linux:**
```bash
sudo pacman -S ffmpeg v4l-utils alsa-utils
```

**Raspberry Pi OS (Debian-based):**
```bash
sudo apt update
sudo apt install ffmpeg v4l-utils alsa-utils
```

### Raspberry Pi Performance Notes

| Model | RAM | Max Resolution | Notes |
|-------|-----|----------------|-------|
| **Pi 5** | 4GB/8GB | 1080p60 | Best performance, handles high bitrates easily |
| **Pi 4** | 4GB+ | 1080p30 | Solid choice, recommended minimum |
| **Pi 4** | 2GB | 720p30 | Works but limited headroom |
| **Pi 3** | 1GB | 720p30 | Usable but may drop frames |
| **Pi Zero** | - | - | Not recommended for video encoding |

**Raspberry Pi 5 Specifics:**
- Uses USB-C power (5V/5A recommended for full performance)
- Has two USB 3.0 ports (blue) - use these for the Ripsaw HD
- Can handle 1080p60 with higher bitrates:
  ```bash
  make stream-udp RESOLUTION=1920x1080 FRAMERATE=60 VIDEO_BITRATE=8000k
  ```
- Runs cooler than Pi 4 but active cooling still recommended for sustained streaming
- PCIe slot available for NVMe SSD (not needed for streaming, but useful for recording)

**Raspberry Pi 4 Settings:**
```bash
# 1080p30 (default, works well)
make stream-udp TARGET_IP=192.168.1.100

# If experiencing issues, drop to 720p
make stream-udp RESOLUTION=1280x720 VIDEO_BITRATE=2500k
```

**Raspberry Pi 3 Settings:**
```bash
# Use 720p with lower bitrate
make stream-udp RESOLUTION=1280x720 VIDEO_BITRATE=2000k FRAMERATE=24
```
