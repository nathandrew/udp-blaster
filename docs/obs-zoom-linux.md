# OBS → Zoom on Linux (Arch / Debian / Ubuntu)

This guide covers the **receiver** side: making OBS's output available to Zoom (or any conferencing app) as a virtual camera and microphone.

```
[UDP stream] → [OBS Studio] → [v4l2loopback]   → [Zoom Camera]
                            → [PipeWire null sink monitor] → [Zoom Microphone]
```

If you just need the commands and don't care how it works, jump to [TL;DR](#tldr).

---

## How it works

Linux doesn't have a built-in virtual camera or virtual microphone, so we use two kernel/userspace shims:

- **Virtual camera:** the [`v4l2loopback`](https://github.com/v4l2loopback/v4l2loopback) kernel module exposes a fake `/dev/videoN` device that OBS writes frames into. Zoom and Chrome read from it like any other webcam.
- **Virtual audio:** PipeWire (or PulseAudio) `module-null-sink` creates a fake audio output. Anything sent to that sink shows up as a `.monitor` source that Zoom can pick as a microphone.

The Makefile wraps both behind `make virtual-*` targets so you don't have to remember the `modprobe` and `pactl` invocations.

---

## TL;DR

```bash
make virtual-install   # one-time: installs v4l2loopback, pipewire-pulse, qpwgraph
make virtual-start     # loads the kernel module + creates the audio sink
# (configure OBS — see below)
make virtual-verify    # samples the sink to confirm audio is actually flowing
# ...use Zoom...
make virtual-stop      # tear down when done (optional)
```

Or the all-in-one launcher:
```bash
make obs-to-zoom       # = virtual-start + opens OBS + prints checklist
```

---

## OBS settings — three steps, in order

After `make virtual-start`, configure OBS once:

1. **Settings → Audio → Advanced → Monitoring Device** = `OBS-to-Zoom`
2. **Audio Mixer → ⚙ gear** on each source you want Zoom to hear → **Advanced Audio Properties** → **Audio Monitoring** = **Monitor and Output**
   > ⚠️ **This is the #1 cause of "camera works but no audio".** The default is "Monitor Off", which sends nothing to the monitoring device. You must change it for **every** audio source individually.
3. **Controls dock → Start Virtual Camera**

---

## Zoom settings

1. **Settings → Video → Camera** = `OBS Virtual Camera`
2. **Settings → Audio → Microphone** = `Monitor of OBS-to-Zoom`
3. **Uncheck** "Automatically adjust microphone volume" — otherwise Zoom will fight OBS's levels.

---

## Verify

```bash
make virtual-verify
```

This:
1. Confirms `/dev/video10` exists.
2. Confirms the `obs-to-zoom` PipeWire sink exists.
3. Samples the sink for 3 seconds via `parec` and reports the peak.

If the peak is zero, it prints the exact OBS setting to fix (almost always step 2 above — the "Monitor and Output" toggle).

---

## What `make virtual-start` actually does

```bash
sudo modprobe v4l2loopback devices=1 video_nr=10 \
    card_label="OBS Virtual Camera" exclusive_caps=1

pactl load-module module-null-sink \
    sink_name=obs-to-zoom \
    sink_properties=device.description=OBS-to-Zoom \
    channel_map=stereo
```

Two notes:

- `exclusive_caps=1` is required for Zoom and Chrome to enumerate the device. Without it the camera shows up in some apps and not others.
- We use **one** null sink, not two. Zoom picks `Monitor of OBS-to-Zoom` as its mic. Older guides create a second `Audio/Source/Virtual` module and link it with `pw-link`; that pattern looks correct in `pactl` but **silently fails** to enumerate as a recordable input in many apps including Zoom. The `.monitor` of a null sink is reliable.

---

## What `make virtual-stop` does

```bash
pactl unload-module <obs-to-zoom module id>   # for each obs-to-zoom module
sudo modprobe -r v4l2loopback
```

You don't *need* to stop them — they cost essentially nothing to leave loaded. `make virtual-stop` exists for cleanliness and for kernel-update reboots.

---

## Making it persistent across reboots (optional)

If you'd rather not type `make virtual-start` every boot:

```bash
echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf
echo 'options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1' | sudo tee /etc/modprobe.d/v4l2loopback.conf
```

For the audio sink, drop a script in your shell startup or put it in a systemd user unit:
```bash
pactl load-module module-null-sink \
    sink_name=obs-to-zoom \
    sink_properties=device.description=OBS-to-Zoom \
    channel_map=stereo
```

---

## GUI alternative for routing — `qpwgraph`

If you want to see PipeWire connections visually:
```bash
sudo pacman -S qpwgraph    # Arch
sudo apt install qpwgraph  # Debian/Ubuntu
qpwgraph &
```
You should see the OBS process node connected to `obs-to-zoom`, and `obs-to-zoom`'s monitor connected (or connectable) to Zoom.

---

## Quick checklist

| Step | Action | Command / location |
|---|---|---|
| 1 | Install deps | `make virtual-install` |
| 2 | Load camera + sink | `make virtual-start` |
| 3 | OBS Monitoring Device = `OBS-to-Zoom` | OBS Settings → Audio → Advanced |
| 4 | Per-source: Monitor and Output | OBS Mixer → ⚙ → Advanced Audio Properties |
| 5 | Start Virtual Camera | OBS Controls dock |
| 6 | Zoom camera = `OBS Virtual Camera` | Zoom Settings → Video |
| 7 | Zoom mic = `Monitor of OBS-to-Zoom` | Zoom Settings → Audio |
| 8 | Verify audio flowing | `make virtual-verify` |
