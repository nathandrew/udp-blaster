# UDP Blaster

```
                                        ┌───┬───┬───┬───┬───┐
                                        │ ▶ │ ▶ │ ▶ │ ▶ │ ▶ │
            _____________               ├───┼───┼───┼───┼───┤
           /             \              │ ▶ │ ▶ │ ▶ │ ▶ │ ▶ │
    ┌─────┬───────────────┬─===========─┴───┴───┴───┴───┴───┘
    │ UDP │░░░░░░░░░░░░░░░│>
    └─────┴───────────────┴─===========─┬───┬───┬───┬───┬───┐
           \_____________/              │ ▶ │ ▶ │ ▶ │ ▶ │ ▶ │
                  │                     ├───┼───┼───┼───┼───┤
                  │                     │ ▶ │ ▶ │ ▶ │ ▶ │ ▶ │
                 ╱╲                     └───┴───┴───┴───┴───┘

         ╦ ╦ ╔╦╗ ╔═╗   ╔╗  ╦  ╔═╗ ╔═╗ ╔╦╗ ╔═╗ ╦═╗
         ║ ║  ║║ ╠═╝   ╠╩╗ ║  ╠═╣ ╚═╗  ║  ║╣  ╠╦╝
         ╚═╝ ═╩╝ ╩     ╚═╝ ╩═╝╩ ╩ ╚═╝  ╩  ╚═╝ ╩╚═
```

Stream video/audio from Razer Ripsaw HD to another device running OBS via UDP.

## Architecture

```
[Camera/Source] → [Ripsaw HD] → [This Linux PC] → [Network] → [OBS PC] → [Zoom]
                                    ffmpeg           UDP        OBS
```

## Quick Start

```bash
# 1. Run interactive setup
make setup

# 2. Test locally
make test-video

# 3. Stream to OBS machine
make stream
```

## Available Commands

| Command | Description |
|---------|-------------|
| `make setup` | Interactive setup (select devices, save config) |
| `make detect` | Detect video/audio devices |
| `make find-pi` | Find Raspberry Pi on network |
| `make my-ip` | Show this machine's IP address |
| `make ssh-pi` | SSH into the Pi |
| `make test-video` | Preview video locally (no streaming) |
| `make test-audio` | Test audio levels |
| `make test-receive` | Open VLC to receive stream (run on OBS machine) |
| `make stream` | Start streaming to OBS |
| `make stop` | Stop any running streams |
| `make virtual-check` | Check if virtual camera/audio dependencies are installed |
| `make virtual-install` | Install virtual device dependencies (Arch/Debian) |
| `make virtual-start` | Load virtual camera + create virtual audio sink |
| `make virtual-stop` | Unload virtual camera + remove virtual audio sink |
| `make virtual-status` | Show status of virtual devices |
| `make test-stream` | Send ffmpeg test pattern over UDP to localhost |

**Override settings inline:**
```bash
make stream TARGET_IP=192.168.1.50
make stream RESOLUTION=1280x720 VIDEO_BITRATE=3000k
```

## Technology Overview

### FFmpeg
Command-line tool that captures video/audio from devices and encodes/transmits it. We use it to grab frames from the Ripsaw HD and send them over the network.

### V4L2 (Video4Linux2)
Linux kernel interface for video capture devices. Your Ripsaw HD appears as `/dev/videoX`. FFmpeg reads from this device.

### ALSA
Linux audio system. The Ripsaw HD's audio appears as a capture device like `hw:2,0`. FFmpeg captures audio through ALSA.

### Encoding Settings

- **libx264**: H.264 video encoder (widely compatible)
- **preset ultrafast**: Minimal CPU usage, some quality tradeoff
- **tune zerolatency**: Removes buffering for live streaming
- **aac**: Audio codec (compatible with everything)

## OBS Setup (Receiving Machine)

1. Add Source → **Media Source**
2. Uncheck "Local File"
3. Input: `udp://@:5000`
4. Check "Restart playback when source becomes active"

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
- Lower resolution: `make stream RESOLUTION=1280x720`
- Ensure both machines are on same network (not through internet)

### Choppy video
- Reduce bitrate: `make stream VIDEO_BITRATE=3000k`
- Lower framerate: `make stream FRAMERATE=24`

## Raspberry Pi Setup Guide

Complete guide for setting up a headless Raspberry Pi (no monitor needed) for UDP streaming.

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
git clone https://github.com/nathandrew/udp-blaster.git
cd udp-blaster
```

**Option B - Copy from your computer:**
```bash
# Run this FROM your laptop (not the Pi)
scp -r /path/to/udp-blaster pi@churchpi.local:~/
```

---

### Step 6: Connect and Configure Ripsaw HD

1. Plug the Razer Ripsaw HD into a USB 3.0 port (blue port)
2. Connect your camera/video source to the Ripsaw's HDMI input
3. Detect the devices:

```bash
cd ~/udp-blaster
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
make stream TARGET_IP=192.168.1.100
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
| Start UDP stream | `make stream TARGET_IP=<ip>` |
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

## OBS to Zoom (Virtual Camera & Microphone)

Once OBS is receiving the UDP stream, you need virtual devices so Zoom can use OBS's output as a camera and microphone.

```
[UDP Stream] → [OBS Studio] → [Virtual Camera] → [Zoom Video Source]
                             → [Virtual Audio]  → [Zoom Microphone]
```

### Virtual Camera (v4l2loopback)

OBS has a built-in "Start Virtual Camera" feature on Linux, but it requires the `v4l2loopback` kernel module.

**Arch Linux:**
```bash
sudo pacman -S v4l2loopback-dkms linux-headers
```

**Debian/Ubuntu:**
```bash
sudo apt install v4l2loopback-dkms v4l2loopback-utils linux-headers-$(uname -r)
```

**Load the module:**
```bash
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
```

> `exclusive_caps=1` is required for Zoom and Chrome to detect the device.

**Make it persistent across reboots:**
```bash
# Create module config
echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf

# Set options
echo 'options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1' | sudo tee /etc/modprobe.d/v4l2loopback.conf
```

**Verify it's working:**
```bash
v4l2-ctl --list-devices
# Should show "OBS Virtual Camera" at /dev/video10
```

**In OBS:**
1. Click **Start Virtual Camera** in the bottom-right controls
2. The virtual camera is now broadcasting whatever OBS is showing

**In Zoom:**
1. Go to **Settings → Video**
2. Select **OBS Virtual Camera** from the camera dropdown
3. You should see your OBS output as the Zoom video

### Virtual Microphone (PipeWire / PulseAudio)

To route OBS audio output into Zoom as a microphone input, you create a virtual audio sink and monitor it.

#### Option A: PipeWire (modern Linux - Arch, Fedora, Ubuntu 22.04+)

Most modern distros use PipeWire. Check with:
```bash
pactl info | grep "Server Name"
# Should show "PulseAudio (on PipeWire)" if using PipeWire
```

**Create a virtual sink:**
```bash
# Create a virtual sink that OBS will output to
pactl load-module module-null-sink media.class=Audio/Sink sink_name=obs-to-zoom channel_map=stereo
pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=obs-to-zoom-source channel_map=stereo
```

> The above creates both a sink (for OBS to send audio to) and a virtual source (for Zoom to read from).

**Wire them together using `pw-link`:**
```bash
# List available ports
pw-link -o  # outputs
pw-link -i  # inputs

# Connect the null sink monitor to the virtual source
pw-link "obs-to-zoom:monitor_FL" "obs-to-zoom-source:input_FL"
pw-link "obs-to-zoom:monitor_FR" "obs-to-zoom-source:input_FR"
```

**Simpler alternative — use `qpwgraph` (GUI):**
```bash
sudo pacman -S qpwgraph   # Arch
sudo apt install qpwgraph  # Debian/Ubuntu
qpwgraph &
```
Then visually drag connections from OBS output to the virtual source input.

**In OBS:**
1. Go to **Settings → Audio → Advanced**
2. Set **Monitoring Device** to **obs-to-zoom** (the null sink)
3. In the Audio Mixer, click the gear icon on your audio source
4. Select **Advanced Audio Properties**
5. Set **Audio Monitoring** to **Monitor and Output** for the sources you want Zoom to hear

**In Zoom:**
1. Go to **Settings → Audio**
2. Select **obs-to-zoom-source** (or "Null Output") as the **Microphone**
3. Test that audio levels show up in the Zoom mic meter

#### Option B: PulseAudio (older systems)

```bash
# Create virtual sink
pactl load-module module-null-sink sink_name=obs-to-zoom sink_properties=device.description="OBS-to-Zoom"

# The monitor of this sink becomes a microphone source
# It will appear as "Monitor of OBS-to-Zoom" in Zoom's mic list
```

**In OBS:** Same as PipeWire steps above — set Monitoring Device to the null sink.

**In Zoom:** Select **Monitor of OBS-to-Zoom** as the microphone.

#### Make virtual audio persistent

Add to your shell startup or create a script:
```bash
#!/bin/bash
# save as ~/obs-zoom-audio.sh
pactl load-module module-null-sink media.class=Audio/Sink sink_name=obs-to-zoom channel_map=stereo
pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=obs-to-zoom-source channel_map=stereo
pw-link "obs-to-zoom:monitor_FL" "obs-to-zoom-source:input_FL"
pw-link "obs-to-zoom:monitor_FR" "obs-to-zoom-source:input_FR"
echo "Virtual audio devices created and linked"
```

### Quick Checklist: OBS → Zoom

| Step | Action |
|------|--------|
| 1 | Install v4l2loopback and load the module |
| 2 | Create virtual audio sink (PipeWire or PulseAudio) |
| 3 | In OBS: Start Virtual Camera |
| 4 | In OBS: Set Monitoring Device to the virtual sink |
| 5 | In OBS: Set audio sources to "Monitor and Output" |
| 6 | In Zoom: Select "OBS Virtual Camera" for video |
| 7 | In Zoom: Select virtual source for microphone |
| 8 | Test both video and audio in Zoom settings before the call |

---

## Testing Locally Without a UDP Stream

When you don't have a Ripsaw HD or UDP stream available, you can still test the full OBS → Zoom pipeline using sample media.

### Option 1: Play a Sample Video in OBS

1. Download a sample video (or use any video file you have):
   ```bash
   # Download Big Buck Bunny (open-source test video, 720p, ~60MB)
   wget -O ~/sample-video.mp4 "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"

   # Or use ffmpeg to generate a test pattern with audio (no download needed)
   ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 \
          -f lavfi -i sine=frequency=440:sample_rate=48000 \
          -t 60 -c:v libx264 -c:a aac ~/test-pattern.mp4
   ```

2. In OBS, add a **Media Source**:
   - Click **+** under Sources → **Media Source**
   - Check **Local File**
   - Browse to your video file
   - Check **Loop** to keep it playing continuously

3. Start the Virtual Camera and test in Zoom as described above.

### Option 2: Use a VLC Window Capture

1. Open any video in VLC
2. In OBS, add a **Window Capture** source
3. Select the VLC window
4. This captures whatever VLC is playing

### Option 3: Screen/Window Capture

If you just want to verify the OBS → Zoom pipeline works:

1. In OBS, add a **Screen Capture** or **Window Capture** source
2. This captures your desktop — useful for quick testing
3. Start Virtual Camera and verify it shows up in Zoom

### Option 4: Simulate a UDP Stream Locally

Send a test pattern over UDP to OBS on the same machine:
```bash
# Terminal 1: Send a test stream to localhost
ffmpeg -re \
    -f lavfi -i testsrc2=size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -c:v libx264 -preset ultrafast -tune zerolatency -b:v 4500k \
    -c:a aac -b:a 192k -ar 48000 \
    -f mpegts "udp://127.0.0.1:5000?pkt_size=1316"
```

Then in OBS:
1. Add **Media Source** → uncheck "Local File" → input: `udp://@:5000`
2. This simulates the exact same setup as receiving from the Pi/streaming machine

> This is the best way to test the full pipeline end-to-end without any hardware.

### Option 5: Use Your Webcam as a Placeholder

1. In OBS, add a **Video Capture Device** source
2. Select your built-in webcam
3. This acts as a stand-in for the Ripsaw HD input

---

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
  make stream RESOLUTION=1920x1080 FRAMERATE=60 VIDEO_BITRATE=8000k
  ```
- Runs cooler than Pi 4 but active cooling still recommended for sustained streaming
- PCIe slot available for NVMe SSD (not needed for streaming, but useful for recording)

**Raspberry Pi 4 Settings:**
```bash
# 1080p30 (default, works well)
make stream TARGET_IP=192.168.1.100

# If experiencing issues, drop to 720p
make stream RESOLUTION=1280x720 VIDEO_BITRATE=2500k
```

**Raspberry Pi 3 Settings:**
```bash
# Use 720p with lower bitrate
make stream RESOLUTION=1280x720 VIDEO_BITRATE=2000k FRAMERATE=24
```
