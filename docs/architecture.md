# Architecture & Technology

UDP Blaster is intentionally a thin Makefile wrapper around `ffmpeg` plus a few OS-specific virtual-device tricks. This document explains what each piece does and why.

---

## The pipeline

```
┌──────────────┐  HDMI  ┌────────────┐  USB 3.0  ┌─────────────┐
│ Camera/laptop│ ─────▶ │ Ripsaw HD  │ ────────▶ │   Sender    │
│ HDMI source  │        │ (capture)  │           │ (Pi/Arch/Mac│
└──────────────┘        └────────────┘           │   ffmpeg)   │
                                                 └──────┬──────┘
                                                        │ MPEG-TS
                                                        │ over UDP:5000
                                                        ▼
                                                 ┌─────────────┐
                                                 │  Receiver   │
                                                 │ (Arch/Mac   │
                                                 │  + OBS)     │
                                                 └──────┬──────┘
                                                        │ virtual cam +
                                                        │ virtual mic
                                                        ▼
                                                 ┌─────────────┐
                                                 │    Zoom     │
                                                 │ (or any app)│
                                                 └─────────────┘
```

Two distinct sides:

- **Sender** runs `ffmpeg` to read the capture device, h.264-encode the video, AAC-encode the audio, mux into MPEG-TS, and `udp://target:5000` it over the network. This is what `make stream` does.
- **Receiver** runs OBS, which ingests the UDP stream as a Media Source. OBS then exposes its program output to other apps via a virtual camera and a routed audio sink. This is what `make virtual-*` and the OBS+Zoom guides set up.

The sender doesn't know or care what's on the receiving end. The receiver doesn't know or care where the stream came from. UDP is one-way, fire-and-forget — there's no handshake to negotiate, which is why latency is low and recovery is "do nothing, the next packet will arrive."

---

## Why MPEG-TS over UDP?

- **MPEG-TS** is the standard container for broadcast streams. It tolerates packet loss gracefully — losing a packet drops a few frames, it doesn't desync the stream forever like a damaged MP4 would.
- **UDP** has no retry, no congestion control, and no connection setup. For a LAN with a real-time signal you don't *want* TCP's retries — by the time a retried packet arrives the moment is gone, and the retransmit storm makes things worse.
- **`pkt_size=1316`** in the URL keeps each UDP packet under the typical 1500-byte MTU after IP+UDP+RTP headers, avoiding fragmentation.

---

## ffmpeg

The single most important tool. It does:

- Capture from the OS-native video/audio API
- Encode video with `libx264` and audio with `aac`
- Mux into MPEG-TS
- Send over UDP

The Makefile's `stream` target boils down to:

```bash
ffmpeg \
  -f <video-input> -framerate 30 -video_size 1920x1080 -i <video-dev> \
  -f <audio-input> -i <audio-dev> \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 4500k \
  -c:a aac -b:a 192k -ar 48000 \
  -f mpegts "udp://<target>:5000?pkt_size=1316"
```

The `<input>` flags differ by OS — see below.

### Encoder choices

| Flag | Why |
|---|---|
| `-c:v libx264` | h.264, decoded by everything |
| `-preset ultrafast` | Minimal CPU, some quality cost. The Pi can't keep up with slower presets at 1080p. |
| `-tune zerolatency` | Disables B-frames and lookahead so frames go out as soon as they're encoded |
| `-b:v 4500k` | Reasonable 1080p30 bitrate; tune for your network |
| `-c:a aac` | Universal audio codec |
| `-ar 48000` | Standard for video; matches what most capture devices output |

---

## Capture APIs by OS

The capture front-end is the only platform-specific part of the sender pipeline. The Makefile auto-detects the platform via `uname -s` and switches `ffmpeg` input flags accordingly.

### Linux (Pi, Arch, Debian, Ubuntu)

- **V4L2 (Video4Linux2)** is the kernel video API. Capture devices appear as `/dev/videoN`. ffmpeg reads them via `-f v4l2 -i /dev/video0`.
- **ALSA** is the kernel audio API. Capture devices appear as `hw:CARD,DEVICE` strings. ffmpeg reads them via `-f alsa -i hw:2,0`.
- Discovery: `v4l2-ctl --list-devices` for video, `arecord -l` for audio. `make detect` runs both.

### macOS

- **AVFoundation** is the unified media-capture framework — both video and audio devices live under one indexed list. ffmpeg reads them via a single combined input: `-f avfoundation -i "0:1"` (video index 0, audio index 1).
- Discovery: `ffmpeg -f avfoundation -list_devices true -i ""` prints both lists. `make detect` runs that.
- Permissions: macOS gates camera/mic access via TCC. ffmpeg needs to be granted permission via **System Settings → Privacy & Security**, otherwise capture silently returns nothing.

---

## Virtual devices on the receiver

OBS produces one program output. To get that into Zoom you need an OS-level virtual camera and an OS-level virtual microphone — apps that look like real input devices to other apps.

### Linux

- **Virtual camera:** the [`v4l2loopback`](https://github.com/v4l2loopback/v4l2loopback) kernel module exposes a fake `/dev/videoN` (we use `/dev/video10`). OBS writes frames into it; Zoom and Chrome read frames out. Loaded with `modprobe v4l2loopback ... exclusive_caps=1` (the flag is required for Zoom and Chrome to enumerate the device).
- **Virtual microphone:** PipeWire (or PulseAudio) `module-null-sink` creates a "speaker" that goes nowhere. OBS sends audio to it as a monitoring device, and the sink's `.monitor` source — automatically created by PipeWire — appears in any app that can record audio. Zoom picks it as **"Monitor of OBS-to-Zoom"**.

We use **one** null sink rather than the older "two sinks + `pw-link`" pattern because that pattern silently fails to enumerate as a recordable input in many apps, including Zoom.

Both pieces are loaded by `make virtual-start` and torn down by `make virtual-stop`.

### macOS

- **Virtual camera:** built into OBS Studio since 26.1, via a CoreMediaIO DAL plugin shipped with the OBS package. There's nothing for the shell to load — clicking *Start Virtual Camera* in OBS makes `OBS Virtual Camera` visible to every camera-aware app on the system.
- **Virtual microphone:** [BlackHole](https://github.com/ExistentialAudio/BlackHole) is a free CoreAudio HAL driver. Once installed (`brew install blackhole-2ch`), **BlackHole 2ch** appears as a real input device in both OBS and Zoom. No routing dance, no monitor-of indirection.

`make virtual-start` and `make virtual-stop` are no-ops on macOS — they just print the OBS+Zoom configuration checklist for parity with the Linux flow.

---

## The "Monitor and Output" gotcha

This trips people up on every OS, and it's purely an OBS-side setting:

In OBS, setting **Settings → Audio → Advanced → Monitoring Device** does **not** by itself send any audio to that device. Each individual audio source in the Mixer must *also* have its **Audio Monitoring** mode set to **"Monitor and Output"** (in Advanced Audio Properties, accessible via the gear icon).

The default for every source is **"Monitor Off"**, which sends nothing to the monitoring device — even though it correctly plays the audio in the OBS preview. This is why people get a working virtual camera in Zoom but no microphone signal.

The `make virtual-start` and `make virtual-verify` targets both call this out prominently because it's the single most common setup mistake.

---

## File map

| File | Purpose |
|---|---|
| `Makefile` | All commands. OS-detection at top via `uname -s`, then `ifeq ($(PLATFORM),mac)` branches. |
| `setup.sh` | Interactive device picker. Detects Darwin vs Linux, writes `.config.mk`. |
| `.config.mk` | Generated, gitignored. Holds your saved `VIDEO_DEV`, `AUDIO_DEV`, `TARGET_IP`. |
| `docs/` | All long-form docs (this folder). |
| `README.md` | Landing page only — pitch, quick start, command cheat sheet, links into `docs/`. |

---

## Why Make?

Because the operations you actually run while debugging this are short, they have OS-specific variations, they need named arguments (`TARGET_IP=...`), and they benefit from OS detection at parse time. A shell script would also work, but `make` gives you free target listing (`make help`) and tab completion in most shells, and the conditional `ifeq` blocks make per-OS branching very obvious in source.

There is no actual "build" — every target is `.PHONY`.
