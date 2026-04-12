# Streaming Guide

End-to-end flow for sending a UDP stream from a capture device on the sender machine to OBS on a receiver machine.

```
[HDMI source] → [Ripsaw HD] → [Sender: Pi/Arch/Mac] → UDP/network → [Receiver: Arch/Mac + OBS]
                                  ffmpeg                                   Media Source
```

The Pi is the canonical sender; the receiver is whatever desktop runs OBS + Zoom.

---

## 1. Pick your devices on the sender

```bash
make detect
```

**On Linux (Pi/Arch)** this lists `/dev/videoN` paths from `v4l2-ctl` and ALSA cards from `arecord -l`. Look for "Ripsaw" and note its device path and ALSA card number.

Example:
```
Razer Ripsaw HD (usb-0000:00:14.0-1):
        /dev/video0
        /dev/video1

card 2: Ripsaw [Razer Ripsaw HD], device 0: USB Audio
```
Use `VIDEO_DEV=/dev/video0` and `AUDIO_DEV=hw:2,0` (format: `hw:CARD,DEVICE`).

**On macOS** this lists AVFoundation devices by index:
```
[AVFoundation indev @ ...] AVFoundation video devices:
[AVFoundation indev @ ...] [0] FaceTime HD Camera
[AVFoundation indev @ ...] [1] Razer Ripsaw HD
[AVFoundation indev @ ...] AVFoundation audio devices:
[AVFoundation indev @ ...] [0] Razer Ripsaw HD
[AVFoundation indev @ ...] [1] MacBook Pro Microphone
```
Use `VIDEO_DEV=1` and `AUDIO_DEV=0` (the numeric indices).

---

## 2. Save your config

```bash
make setup
```

Interactive picker: select video device, audio device, target IP. Writes to `.config.mk` (which is gitignored). After setup you can just run `make stream` without arguments.

You can also override inline at any time:
```bash
make stream TARGET_IP=192.168.1.50 RESOLUTION=1280x720 VIDEO_BITRATE=3000k
```

Available variables:

| Variable | Default | Notes |
|---|---|---|
| `VIDEO_DEV` | `/dev/video0` (Linux) / `0` (Mac) | Capture video device |
| `AUDIO_DEV` | `hw:0,0` (Linux) / `0` (Mac) | Capture audio device |
| `TARGET_IP` | `192.168.1.100` | Receiver machine IP |
| `UDP_PORT` | `5000` | |
| `RESOLUTION` | `1920x1080` | |
| `FRAMERATE` | `30` | |
| `VIDEO_BITRATE` | `4500k` | |
| `AUDIO_BITRATE` | `192k` | |
| `AUDIO_RATE` | `48000` | |

---

## 3. Find the receiver's IP

On the receiver machine:
```bash
make my-ip
```
Or natively: `ip addr` (Linux) / `ipconfig getifaddr en0` (macOS) / `ipconfig` (Windows).

---

## 4. Test capture before going live

On the sender:
```bash
make test-video    # opens an ffplay preview window
make test-audio    # samples audio for 3 seconds (Mac) or shows level meter (Linux)
```

If video is black or audio is silent, see [Troubleshooting](#troubleshooting) below.

---

## 5. Start streaming

On the receiver, configure OBS to listen first (one-time):

1. Add Source → **Media Source**
2. **Uncheck** "Local File"
3. Input: `udp://@:5000`
4. Check "Restart playback when source becomes active"

Then on the sender:
```bash
make stream
```

Or override the target inline:
```bash
make stream TARGET_IP=192.168.1.50
```

The receiver should see the video and hear the audio in OBS within a second or two. To stop, hit `Ctrl+C` on the sender (or `make stop` from another terminal).

---

## 6. (Optional) Verify with VLC instead of OBS

If you don't have OBS configured yet, you can pop a quick VLC viewer on the receiver:
```bash
make test-receive
```
Opens `vlc udp://@:5000`. Useful for confirming the stream is reaching the receiver before fighting with OBS settings.

---

## Local end-to-end test (no Pi/network needed)

`make test-stream` sends an ffmpeg test pattern (color bars + 440 Hz sine) to `udp://127.0.0.1:5000`. Run it in one terminal, point OBS at `udp://@:5000` in another, and you've simulated the full pipeline locally. See [`testing.md`](testing.md) for more options.

---

## Next step: virtual devices for Zoom

Once OBS is receiving the stream, you'll want to expose it to Zoom (or any conferencing app) as a virtual camera and microphone:

- Linux receiver: [`obs-zoom-linux.md`](obs-zoom-linux.md)
- macOS receiver: [`obs-zoom-macos.md`](obs-zoom-macos.md)

Or run the all-in-one:
```bash
make obs-to-zoom
```
which loads the virtual devices, launches OBS, and prints the OBS+Zoom configuration checklist.

---

## Troubleshooting

### "Device or resource busy"
Another program is using the capture card. Close OBS, VLC, ffplay, browser tabs that might have grabbed the camera, etc.

### Black video / no signal
- Run `make detect` again — the device path can change between reboots.
- Run `make test-video` first; if that's also black, the issue is upstream of UDP Blaster.
- Many capture cards (including the Ripsaw HD) need an active HDMI input signal before they expose any video format. Power-cycle the source.
- On macOS, check that you've granted Camera permission to your terminal in **System Settings → Privacy & Security → Camera**.

### No audio
- **Linux**: `arecord -l` lists ALSA cards; confirm `AUDIO_DEV=hw:CARD,DEVICE` matches.
- **macOS**: `make detect` lists avfoundation audio devices by index. Check the `AUDIO_DEV` index in `.config.mk`.
- On macOS, grant Microphone permission in **System Settings → Privacy & Security → Microphone**.
- Verify audio is actually present at the source — many HDMI capture devices only carry audio when the source is sending it.

### High latency
- Lower the resolution: `make stream RESOLUTION=1280x720`
- Lower the bitrate: `make stream VIDEO_BITRATE=3000k`
- Make sure both machines are on the same LAN segment, not routed through the internet.

### Choppy / dropping frames
- Drop the bitrate or framerate: `make stream VIDEO_BITRATE=3000k FRAMERATE=24`
- Check sender CPU. On a Pi 3, 720p30 is the realistic ceiling — see [`raspberry-pi.md`](raspberry-pi.md) for per-Pi-model recommendations.
- Wired ethernet is much more forgiving than WiFi.

### Stream reaches the receiver in OBS but Zoom shows nothing
That's a virtual-device problem, not a streaming problem. Jump to [`obs-zoom-linux.md`](obs-zoom-linux.md) or [`obs-zoom-macos.md`](obs-zoom-macos.md).
