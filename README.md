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

## Dependencies

Install on Arch Linux:
```bash
sudo pacman -S ffmpeg v4l-utils alsa-utils
```
# church-video
