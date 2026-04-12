# Installation

UDP Blaster has two roles:

- **Sender** — captures from a Razer Ripsaw HD (or any v4l2 / avfoundation device) and pushes a UDP stream over the network. Typically a Raspberry Pi.
- **Receiver** — runs OBS Studio, ingests the UDP stream, and exposes it to Zoom (or any conferencing app) via a virtual camera and virtual microphone. Typically a desktop Linux box or a Mac.

You only need the dependencies for the role(s) the machine will play. Most setups have one Pi sender and one desktop receiver, but you can run both roles on the same machine for testing.

---

## Raspberry Pi OS (sender — primary)

The Pi is the canonical streaming source. See [`raspberry-pi.md`](raspberry-pi.md) for the full headless first-boot guide. Once you can SSH into it, install the dependencies:

```bash
sudo apt update
sudo apt install -y ffmpeg v4l-utils alsa-utils git make
```

Then clone the repo and run `make detect` — see [`streaming.md`](streaming.md).

---

## Arch Linux

### As a sender

```bash
sudo pacman -S --needed ffmpeg v4l-utils alsa-utils make git
```

That's everything needed to run `make detect`, `make setup`, `make stream`.

### As a receiver (OBS + Zoom)

In addition to the sender deps, install the virtual-device stack:

```bash
make virtual-install
```

That target runs:
```bash
sudo pacman -S --needed v4l2loopback-dkms linux-headers pipewire-pulse qpwgraph
```

You'll also need OBS Studio itself:
```bash
sudo pacman -S obs-studio
```
or via Flatpak: `flatpak install flathub com.obsproject.Studio`.

Verify everything landed:
```bash
make virtual-check
```

Full receiver-side guide: [`obs-zoom-linux.md`](obs-zoom-linux.md).

---

## macOS

### As a sender

```bash
brew install ffmpeg make
```

The first time `make stream` runs, macOS will prompt for camera and microphone access. Approve them in **System Settings → Privacy & Security**.

### As a receiver (OBS + Zoom)

```bash
make virtual-install
```

That target runs:
```bash
brew install blackhole-2ch       # virtual audio driver
brew install --cask obs          # only if OBS not already installed
brew install ffmpeg
```

If Homebrew isn't installed, install it from <https://brew.sh> first.

Verify:
```bash
make virtual-check
```

Full receiver-side guide: [`obs-zoom-macos.md`](obs-zoom-macos.md).

> **macOS is simpler than Linux:** OBS ships its own virtual camera (no kernel module), and BlackHole is one Homebrew package (no `pactl`/`pw-link` dance). The same `make` commands work — the Makefile auto-detects Darwin and switches toolchains.

---

## Debian / Ubuntu (sender or receiver)

```bash
sudo apt install -y ffmpeg v4l-utils alsa-utils make git
```

For the receiver-side virtual devices:
```bash
make virtual-install
```
runs:
```bash
sudo apt install -y v4l2loopback-dkms v4l2loopback-utils \
    linux-headers-$(uname -r) pipewire qpwgraph
```

Plus OBS:
```bash
sudo apt install obs-studio
```

---

## Verify

```bash
make virtual-check    # receiver-side: checks OBS, virtual-device deps, ffmpeg
make detect           # sender-side: lists capture devices
```

Next: [`streaming.md`](streaming.md) for the day-to-day flow.
