# OBS → Zoom on macOS

This guide covers the **receiver** side: making OBS's output available to Zoom (or any conferencing app) as a virtual camera and microphone.

```
[UDP stream] → [OBS Studio] → [Built-in OBS Virtual Camera] → [Zoom Camera]
                            → [BlackHole 2ch (CoreAudio)]   → [Zoom Microphone]
```

macOS is significantly simpler than Linux. The Makefile auto-detects Darwin and switches to the Mac toolchain — same `make` commands, different machinery.

If you just need the commands, jump to [TL;DR](#tldr).

---

## How it works

- **Virtual camera:** OBS Studio ships its own virtual camera on macOS via a CoreMediaIO DAL plugin (since OBS 26.1). No kernel module, no DKMS, no headers. Click *Start Virtual Camera* in OBS and `OBS Virtual Camera` shows up in every camera-aware app on the system.
- **Virtual audio:** [BlackHole](https://github.com/ExistentialAudio/BlackHole) is a free CoreAudio driver. Once installed, **BlackHole 2ch** appears as a real input device in both OBS (as a Monitoring Device) and Zoom (as a Microphone). No `pactl`, no `pw-link`, no second sink, no "Monitor of…" indirection.

Result: virtual camera = zero shell commands, virtual audio = one `brew install`.

---

## TL;DR

```bash
make virtual-install   # one-time: brew install blackhole-2ch + obs + ffmpeg
make virtual-start     # prints the OBS+Zoom checklist (no actual loading needed)
# (configure OBS — see below)
make virtual-verify    # samples BlackHole to confirm audio is actually flowing
# ...use Zoom...
```

There is no `make virtual-stop` work to do on macOS — see [the no-op section](#why-virtual-start--virtual-stop-are-no-ops-on-macos) below.

---

## OBS settings — three steps, in order

After `make virtual-start`, configure OBS once:

1. **Settings → Audio → Advanced → Monitoring Device** = `BlackHole 2ch`
2. **Audio Mixer → ⚙ gear** on each source you want Zoom to hear → **Advanced Audio Properties** → **Audio Monitoring** = **Monitor and Output**
   > ⚠️ **This is the #1 cause of "camera works but no audio".** It's an OBS-side gotcha that applies on every OS — the default is "Monitor Off", which sends nothing to the monitoring device. You must change it for **every** audio source individually.
3. **Controls dock → Start Virtual Camera**

---

## Zoom settings

1. **Settings → Video → Camera** = `OBS Virtual Camera`
2. **Settings → Audio → Microphone** = `BlackHole 2ch`
   > Note: this appears as a real input device — there is no "Monitor of…" prefix like on Linux.
3. **Uncheck** "Automatically adjust microphone volume" — otherwise Zoom will fight OBS's levels.

---

## Verify

```bash
make virtual-verify
```

This:
1. Confirms the BlackHole 2ch driver is installed.
2. Confirms OBS is installed.
3. Samples BlackHole for 3 seconds via `ffmpeg -f avfoundation -i ":BlackHole 2ch" -af volumedetect` and reports the `mean_volume` in dB.

`-91 dB` (or `-inf`) means silence — the verify command then prints the exact OBS setting to fix (almost always step 2 above — the "Monitor and Output" toggle).

---

## Why `virtual-start` & `virtual-stop` are no-ops on macOS

On Linux these targets `modprobe` a kernel module and `pactl load-module` a null sink. On macOS there is genuinely nothing to load:

- The **OBS virtual camera** lives inside the OBS process. It's only visible to other apps while OBS is running and you've clicked *Start Virtual Camera*. Stop it the same way (Controls → Stop Virtual Camera).
- **BlackHole** is a system audio driver loaded by macOS at boot. It stays installed and active until you `brew uninstall blackhole-2ch`.

The targets still exist on Mac for cross-platform parity — `virtual-start` checks that BlackHole and OBS are both installed and prints the configuration checklist, and `virtual-stop` prints a status message. Neither runs any privileged commands.

---

## What `make virtual-install` does

```bash
brew install blackhole-2ch       # CoreAudio virtual driver
brew install --cask obs          # only if /Applications/OBS.app is missing
brew install ffmpeg              # for streaming + virtual-verify
```

If Homebrew isn't installed, install it from <https://brew.sh> first.

---

## Permissions

The first time ffmpeg or OBS accesses your camera and microphone, macOS will pop up TCC permission prompts. Approve them in **System Settings → Privacy & Security**:

- **Camera** — required for `make detect`, `make stream`, OBS, and ffmpeg.
- **Microphone** — required for `make virtual-verify`, `make stream`, and OBS.

If you skipped the prompt, those commands will silently fail or return empty data. You can re-trigger by toggling the app off/on in the privacy panel.

---

## Quick checklist

| Step | Action | Command / location |
|---|---|---|
| 1 | Install deps | `make virtual-install` |
| 2 | Print checklist | `make virtual-start` |
| 3 | OBS Monitoring Device = `BlackHole 2ch` | OBS Settings → Audio → Advanced |
| 4 | Per-source: Monitor and Output | OBS Mixer → ⚙ → Advanced Audio Properties |
| 5 | Start Virtual Camera | OBS Controls dock |
| 6 | Zoom camera = `OBS Virtual Camera` | Zoom Settings → Video |
| 7 | Zoom mic = `BlackHole 2ch` | Zoom Settings → Audio |
| 8 | Verify audio flowing | `make virtual-verify` |
