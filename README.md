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

Stream video and audio from a Razer Ripsaw HD (or any v4l2/avfoundation capture device) over UDP to a desktop running OBS, then expose OBS's output to Zoom as a virtual camera and microphone.

```
[HDMI source] → [Ripsaw HD] → [Sender] ── UDP/network ──→ [Receiver + OBS] → [Zoom]
                                ffmpeg                       virtual cam/mic
```

---

## Platform support

| Role | Platform | Status | Guide |
|---|---|---|---|
| **Sender** (streams UDP) | Raspberry Pi (Pi OS) | ✅ Primary | [docs/raspberry-pi.md](docs/raspberry-pi.md) |
| **Sender** | Arch Linux | ✅ Full | [docs/installation.md#arch-linux](docs/installation.md#arch-linux) |
| **Sender** | macOS | ✅ Full | [docs/installation.md#macos](docs/installation.md#macos) |
| **Sender** | Debian / Ubuntu | ✅ Full | [docs/installation.md#debian--ubuntu-sender-or-receiver](docs/installation.md#debian--ubuntu-sender-or-receiver) |
| **Receiver** (OBS + Zoom) | Arch Linux | ✅ Full | [docs/obs-zoom-linux.md](docs/obs-zoom-linux.md) |
| **Receiver** | macOS | ✅ Full | [docs/obs-zoom-macos.md](docs/obs-zoom-macos.md) |

The Makefile auto-detects the OS via `uname -s` and switches between v4l2/ALSA and avfoundation toolchains. The same `make` commands work on every supported platform.

---

## Quick start

On the **sender** (Pi, Arch, or Mac):

```bash
make virtual-install   # one-time deps for sender; harmless if you only stream
make setup             # interactive: pick devices, set receiver IP
make stream            # go
```

On the **receiver** (Arch or Mac running OBS):

```bash
make virtual-install   # one-time: virtual camera + virtual audio deps
make virtual-start     # load (Linux) or print checklist (Mac)
# configure OBS as the printed checklist instructs
make virtual-verify    # confirm audio is actually flowing into the sink
```

Then in OBS add a **Media Source** with input `udp://@:5000`, and in Zoom select `OBS Virtual Camera` for video and the virtual mic for audio.

Full walkthrough: [docs/streaming.md](docs/streaming.md).

---

## Documentation

| Doc | What's in it |
|---|---|
| [installation.md](docs/installation.md) | Per-OS dependency install (Arch, macOS, Debian, Pi OS) |
| [streaming.md](docs/streaming.md) | Sender-side: detect → setup → stream + troubleshooting |
| [obs-zoom-linux.md](docs/obs-zoom-linux.md) | Receiver-side virtual camera + virtual mic on Linux (v4l2loopback + PipeWire) |
| [obs-zoom-macos.md](docs/obs-zoom-macos.md) | Receiver-side virtual camera + virtual mic on macOS (built-in OBS cam + BlackHole) |
| [raspberry-pi.md](docs/raspberry-pi.md) | Full headless Pi setup from blank SD card to streaming |
| [testing.md](docs/testing.md) | Testing the full pipeline without a Ripsaw or a Pi |
| [architecture.md](docs/architecture.md) | How it works: ffmpeg, V4L2/ALSA/AVFoundation, MPEG-TS, virtual devices |

---

## Commands

Everything UDP Blaster does is one `make` command. Run `make help` for the live list with current config values.

### Sender side

| Command | What it does |
|---|---|
| `make detect` | List available capture devices (v4l2/ALSA on Linux, avfoundation on Mac) |
| `make setup` | Interactive picker — saves to `.config.mk` |
| `make test-video` | Local preview window (no streaming) |
| `make test-audio` | Sample input audio levels |
| `make stream` | Encode and send UDP to `TARGET_IP:5000` |
| `make stop` | Kill any running stream |
| `make test-stream` | Send a test pattern to `udp://127.0.0.1:5000` (no hardware) |

### Receiver side

| Command | What it does |
|---|---|
| `make virtual-check` | Are the virtual-device deps installed? |
| `make virtual-install` | Install deps (auto-detects pacman/apt/brew) |
| `make virtual-start` | Load v4l2loopback + audio sink (Linux) / print checklist (Mac) |
| `make virtual-status` | Show which virtual devices are currently loaded |
| `make virtual-verify` | Sample the virtual audio sink for 3s and report whether OBS is sending audio |
| `make virtual-stop` | Tear down the virtual devices |
| `make obs-to-zoom` | virtual-start + launch OBS + print the OBS+Zoom checklist |
| `make test-receive` | Open VLC at `udp://@:5000` to verify the stream is arriving |

### Network discovery

| Command | What it does |
|---|---|
| `make my-ip` | Show this machine's IP (use this on the receiver) |
| `make find-pi` | Find a Pi on the local network via mDNS, fall back to nmap |
| `make ssh-pi` | SSH into the Pi using `PI_HOSTNAME` |

---

## Configuration overrides

Every variable in the Makefile can be overridden inline or saved to `.config.mk` via `make setup`:

```bash
make stream TARGET_IP=192.168.1.50
make stream RESOLUTION=1280x720 VIDEO_BITRATE=3000k
make stream FRAMERATE=24 AUDIO_BITRATE=128k
```

Common variables:

| Variable | Default | Notes |
|---|---|---|
| `VIDEO_DEV` | `/dev/video0` (Linux) / `0` (Mac) | Capture video device |
| `AUDIO_DEV` | `hw:0,0` (Linux) / `0` (Mac) | Capture audio device |
| `TARGET_IP` | `192.168.1.100` | Receiver machine IP |
| `UDP_PORT` | `5000` | |
| `RESOLUTION` | `1920x1080` | |
| `FRAMERATE` | `30` | |
| `VIDEO_BITRATE` | `4500k` | |
| `PI_HOSTNAME` | `churchpi` | Used by `find-pi` and `ssh-pi` |

---

## Common gotcha: "camera works but no audio"

This trips people up on every OS. It's an OBS-side setting that nothing else can fix:

> In OBS, **Settings → Audio → Advanced → Monitoring Device** alone does nothing. Each audio source in the Mixer must **also** be switched to **"Monitor and Output"** via gear icon → Advanced Audio Properties. The default is "Monitor Off" — that's why no audio reaches Zoom.

Run `make virtual-verify` to confirm whether audio is actually reaching the sink before joining a call. See [docs/obs-zoom-linux.md](docs/obs-zoom-linux.md) or [docs/obs-zoom-macos.md](docs/obs-zoom-macos.md) for the full step-by-step.
