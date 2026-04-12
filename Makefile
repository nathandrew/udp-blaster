# UDP Blaster - Razer Ripsaw HD to OBS via network
#
# Usage: make <target>
# Run 'make help' to see available commands

# ============================================================================
# CONFIGURATION - Load saved config if exists, otherwise use defaults
# ============================================================================

-include .config.mk

# OS detection — picks Linux (v4l2/alsa/pactl) vs macOS (avfoundation/BlackHole)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  PLATFORM := mac
else
  PLATFORM := linux
endif

# Video / audio capture device defaults (run 'make detect' to find yours)
# On macOS these are avfoundation indices (e.g. "0", "1").
# On Linux they are v4l2/ALSA paths (e.g. /dev/video0, hw:0,0).
ifeq ($(PLATFORM),mac)
  VIDEO_DEV ?= 0
  AUDIO_DEV ?= 0
else
  VIDEO_DEV ?= /dev/video0
  AUDIO_DEV ?= hw:0,0
endif

# Target machine IP (where OBS is running)
TARGET_IP ?= 192.168.1.100

# Raspberry Pi hostname (for find-pi command)
PI_HOSTNAME ?= churchpi

# Network to scan (for find-pi fallback)
NETWORK_SCAN ?= 192.168.1.0/24

# Streaming port
UDP_PORT ?= 5000

# Video settings
RESOLUTION ?= 1920x1080
FRAMERATE ?= 30
VIDEO_BITRATE ?= 4500k

# Audio settings
AUDIO_BITRATE ?= 192k
AUDIO_RATE ?= 48000

# ============================================================================
# STREAMING TARGETS
# ============================================================================

.PHONY: help setup detect find-pi my-ip ssh-pi test-video test-audio test-receive stream stop \
       virtual-check virtual-install virtual-start virtual-stop virtual-status virtual-verify \
       test-stream obs-to-zoom

help:
	@echo "UDP Blaster Commands"
	@echo "===================="
	@echo ""
	@echo "Setup & Testing:"
	@echo "  make setup       - Interactive setup (select devices, save config)"
	@echo "  make find-pi     - Find Raspberry Pi on network"
	@echo "  make my-ip       - Show this machine's IP address"
	@echo "  make ssh-pi      - SSH into the Pi"
	@echo "  make detect      - Detect video/audio devices"
	@echo "  make test-video  - Preview video locally (no streaming)"
	@echo "  make test-audio  - Test audio levels"
	@echo "  make test-receive - Open VLC to receive stream (run on OBS machine)"
	@echo ""
	@echo "Streaming:"
	@echo "  make stream      - Start streaming to OBS"
	@echo "  make stop        - Stop any running streams"
	@echo ""
	@echo "Virtual Devices (OBS → Zoom):"
	@echo "  make virtual-check   - Check if virtual camera/audio dependencies are installed"
	@echo "  make virtual-install - Install virtual device dependencies (auto: pacman/apt/brew)"
	@echo "  make virtual-start   - Load virtual camera + create virtual audio sink"
	@echo "  make virtual-stop    - Unload virtual camera + remove virtual audio sink"
	@echo "  make virtual-status  - Show status of virtual devices"
	@echo "  make virtual-verify  - Check that OBS audio is actually reaching the sink"
	@echo ""
	@echo "Quick Start:"
	@echo "  make obs-to-zoom - Start virtual devices + launch OBS (one command)"
	@echo ""
	@echo "Local Testing (no hardware needed):"
	@echo "  make test-stream - Send ffmpeg test pattern over UDP to localhost"
	@echo ""
	@echo "Current Configuration:"
	@echo "  PI_HOSTNAME=$(PI_HOSTNAME)"
	@echo "  TARGET_IP=$(TARGET_IP)  (OBS machine)"
	@echo "  VIDEO_DEV=$(VIDEO_DEV)"
	@echo "  AUDIO_DEV=$(AUDIO_DEV)"
	@echo ""
	@echo "Override with: make stream TARGET_IP=192.168.1.50"
	@echo ""
	@echo "Full docs: see README.md and the docs/ folder"

# ============================================================================
# INTERACTIVE SETUP
# ============================================================================

setup:
	@./setup.sh

# ============================================================================
# NETWORK / PI DISCOVERY
# ============================================================================

# Find the Raspberry Pi on the network
find-pi:
	@echo "=== Looking for $(PI_HOSTNAME).local ==="
	@ping -c 1 -W 2 $(PI_HOSTNAME).local 2>/dev/null && echo "Found via mDNS!" || \
	(echo "mDNS lookup failed, scanning network $(NETWORK_SCAN)..." && \
	echo "This may take 10-30 seconds..." && \
	nmap -sn $(NETWORK_SCAN) 2>/dev/null | grep -B2 -i "raspberry\|$(PI_HOSTNAME)" || \
	echo "No Raspberry Pi found. Check: 1) Pi is powered on 2) Connected to same network 3) Try different NETWORK_SCAN range")

# Show this machine's IP address
my-ip:
	@echo "=== Your IP Address ==="
	@ip -4 addr show dev $$(ip route show default | awk '{print $$5}' | head -1) | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "No network connection found"
	@echo ""
	@echo "Tell the streaming machine to use:"
	@echo "  make stream TARGET_IP=$$(ip -4 addr show dev $$(ip route show default | awk '{print $$5}' | head -1) | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"

# SSH into the Pi
ssh-pi:
	@echo "Connecting to $(PI_HOSTNAME).local..."
	ssh $(PI_HOSTNAME).local

# Detect available devices
ifeq ($(PLATFORM),mac)
detect:
	@echo "=== AVFoundation Devices (macOS) ==="
	@echo "Use the [N] index as VIDEO_DEV / AUDIO_DEV in .config.mk"
	@echo ""
	@ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | grep -E "AVFoundation|\[[0-9]+\]" || echo "ffmpeg not installed: brew install ffmpeg"
else
detect:
	@echo "=== Video Devices ==="
	@v4l2-ctl --list-devices 2>/dev/null || echo "Install v4l-utils: sudo pacman -S v4l-utils"
	@echo ""
	@echo "=== Audio Devices ==="
	@arecord -l 2>/dev/null || echo "Install alsa-utils: sudo pacman -S alsa-utils"
	@echo ""
	@echo "=== Device Formats ($(VIDEO_DEV)) ==="
	@v4l2-ctl -d $(VIDEO_DEV) --list-formats-ext 2>/dev/null | head -30 || echo "Device not found"
endif

# Preview video locally
ifeq ($(PLATFORM),mac)
test-video:
	@echo "Opening preview window... Press Q to quit"
	ffplay -f avfoundation -framerate $(FRAMERATE) -video_size $(RESOLUTION) -i "$(VIDEO_DEV)"
else
test-video:
	@echo "Opening preview window... Press Q to quit"
	ffplay -f v4l2 -framerate $(FRAMERATE) -video_size $(RESOLUTION) $(VIDEO_DEV)
endif

# Test audio levels
ifeq ($(PLATFORM),mac)
test-audio:
	@echo "Sampling audio for 3 seconds from avfoundation device :$(AUDIO_DEV)..."
	@echo "Make some noise — the mean_volume line should be louder than -91 dB"
	@echo ""
	@ffmpeg -hide_banner -f avfoundation -i ":$(AUDIO_DEV)" -t 3 -af volumedetect -f null - 2>&1 | grep -E "mean_volume|max_volume" || echo "Capture failed — check 'make detect' for the right index"
else
test-audio:
	@echo "Monitoring audio levels... Press Ctrl+C to stop"
	@echo "You should see meter movement when there's sound"
	@echo ""
	arecord -D $(AUDIO_DEV) -vvv -f cd -c 2 -r 48000 /dev/null 2>&1
endif

# Receive and display UDP stream (run on receiving machine to test)
test-receive:
	@echo "Opening VLC to receive UDP stream on port $(UDP_PORT)..."
	@echo "Run 'make stream' on the streaming machine first!"
	@echo ""
	vlc udp://@:$(UDP_PORT)

# ============================================================================
# VIRTUAL DEVICES (OBS → Zoom)
# ============================================================================

# Check if virtual device dependencies are installed
ifeq ($(PLATFORM),mac)
virtual-check:
	@echo "=== Virtual Device Dependencies (macOS) ==="
	@echo ""
	@echo "Virtual Camera:"
	@printf "  Built into OBS ...... " && (test -d "/Applications/OBS.app" && echo "✓ (CoreMediaIO plugin shipped with OBS)" || echo "✗ OBS not installed (run: make virtual-install)")
	@echo ""
	@echo "Virtual Audio (BlackHole):"
	@printf "  BlackHole 2ch ....... " && (test -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" && echo "✓ installed" || echo "✗ NOT INSTALLED (run: make virtual-install)")
	@echo ""
	@echo "Streaming Tools:"
	@printf "  Homebrew ............ " && (command -v brew >/dev/null 2>&1 && echo "✓ installed" || echo "✗ NOT INSTALLED — install from https://brew.sh")
	@printf "  ffmpeg .............. " && (command -v ffmpeg >/dev/null 2>&1 && echo "✓ $$(ffmpeg -version 2>/dev/null | head -1 | awk '{print $$3}')" || echo "✗ NOT INSTALLED (brew install ffmpeg)")
	@printf "  OBS Studio .......... " && (test -d "/Applications/OBS.app" && echo "✓ installed" || echo "✗ NOT INSTALLED (brew install --cask obs)")
else
virtual-check:
	@echo "=== Virtual Device Dependencies ==="
	@echo ""
	@echo "Virtual Camera (v4l2loopback):"
	@printf "  v4l2loopback-dkms ... " && (pacman -Q v4l2loopback-dkms 2>/dev/null | awk '{print "✓ " $$2}' || (dpkg -s v4l2loopback-dkms 2>/dev/null | grep "^Version" | awk '{print "✓ " $$2}' || echo "✗ NOT INSTALLED"))
	@printf "  linux-headers ....... " && (pacman -Q linux-headers 2>/dev/null | awk '{print "✓ " $$2}' || (dpkg -s linux-headers-$$(uname -r) 2>/dev/null | grep "^Version" | awk '{print "✓ " $$2}' || echo "✗ NOT INSTALLED"))
	@printf "  Module loaded ....... " && (lsmod | grep -q v4l2loopback && echo "✓ loaded" || echo "✗ not loaded (run: make virtual-start)")
	@echo ""
	@echo "Virtual Audio (PipeWire/PulseAudio):"
	@printf "  PipeWire ............ " && (command -v pw-link >/dev/null 2>&1 && echo "✓ $$(pw-link --version 2>/dev/null || echo 'installed')" || echo "✗ NOT INSTALLED")
	@printf "  PulseAudio ctl ...... " && (command -v pactl >/dev/null 2>&1 && echo "✓ installed" || echo "✗ NOT INSTALLED")
	@printf "  qpwgraph (optional) . " && (command -v qpwgraph >/dev/null 2>&1 && echo "✓ installed" || echo "- not installed (optional GUI)")
	@echo ""
	@echo "Streaming Tools:"
	@printf "  ffmpeg .............. " && (command -v ffmpeg >/dev/null 2>&1 && echo "✓ $$(ffmpeg -version 2>/dev/null | head -1 | awk '{print $$3}')" || echo "✗ NOT INSTALLED")
	@printf "  v4l2-ctl ............ " && (command -v v4l2-ctl >/dev/null 2>&1 && echo "✓ installed" || echo "✗ NOT INSTALLED")
	@printf "  OBS Studio .......... " && (command -v obs >/dev/null 2>&1 && echo "✓ installed" || (flatpak list 2>/dev/null | grep -qi obs && echo "✓ installed (flatpak)" || echo "✗ NOT INSTALLED"))
endif

# Install virtual device dependencies
ifeq ($(PLATFORM),mac)
virtual-install:
	@echo "=== Installing Virtual Device Dependencies (macOS) ==="
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "✗ Homebrew not installed."; \
		echo "  Install it from https://brew.sh and re-run 'make virtual-install'"; \
		exit 1; \
	fi
	@echo "Installing BlackHole 2ch (virtual audio driver)..."
	@brew install blackhole-2ch
	@echo ""
	@if [ ! -d "/Applications/OBS.app" ]; then \
		echo "Installing OBS Studio..."; \
		brew install --cask obs; \
	else \
		echo "OBS Studio already installed."; \
	fi
	@echo ""
	@echo "Installing ffmpeg..."
	@brew install ffmpeg
	@echo ""
	@echo "Done! On macOS the virtual camera is built into OBS and BlackHole is"
	@echo "a persistent driver — there is nothing to load. Run 'make virtual-start'"
	@echo "to print the OBS+Zoom checklist."
else
virtual-install:
	@echo "=== Installing Virtual Device Dependencies ==="
	@if command -v pacman >/dev/null 2>&1; then \
		echo "Detected Arch Linux"; \
		echo "Installing: v4l2loopback-dkms linux-headers pipewire-pulse qpwgraph"; \
		sudo pacman -S --needed v4l2loopback-dkms linux-headers pipewire-pulse qpwgraph; \
	elif command -v apt >/dev/null 2>&1; then \
		echo "Detected Debian/Ubuntu"; \
		echo "Installing: v4l2loopback-dkms v4l2loopback-utils linux-headers-$$(uname -r) pipewire qpwgraph"; \
		sudo apt install -y v4l2loopback-dkms v4l2loopback-utils linux-headers-$$(uname -r) pipewire qpwgraph; \
	else \
		echo "Unsupported package manager. Install manually:"; \
		echo "  - v4l2loopback-dkms"; \
		echo "  - linux-headers for your kernel"; \
		echo "  - pipewire + pipewire-pulse (or pulseaudio)"; \
		echo "  - qpwgraph (optional)"; \
		exit 1; \
	fi
	@echo ""
	@echo "Done! Run 'make virtual-start' to load virtual devices."
endif

# Load virtual camera and create virtual audio sink
ifeq ($(PLATFORM),mac)
virtual-start:
	@echo "=== Starting Virtual Devices (macOS) ==="
	@echo ""
	@echo "Nothing to load — on macOS:"
	@echo "  • OBS Virtual Camera is built into OBS (CoreMediaIO plugin)"
	@echo "  • BlackHole 2ch is a persistent CoreAudio driver, always active"
	@echo ""
	@if [ ! -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]; then \
		echo "  ✗ BlackHole 2ch not installed — run: make virtual-install"; \
		exit 1; \
	else \
		echo "  ✓ BlackHole 2ch driver present"; \
	fi
	@if [ ! -d "/Applications/OBS.app" ]; then \
		echo "  ✗ OBS not installed — run: make virtual-install"; \
		exit 1; \
	else \
		echo "  ✓ OBS Studio installed"; \
	fi
	@$(MAKE) --no-print-directory _virtual-instructions-mac
else
virtual-start:
	@echo "=== Starting Virtual Devices ==="
	@echo ""
	@echo "Loading virtual camera..."
	@if lsmod | grep -q v4l2loopback; then \
		echo "  v4l2loopback already loaded"; \
	else \
		sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1 && \
		echo "  ✓ Virtual camera loaded at /dev/video10"; \
	fi
	@echo ""
	@echo "Creating virtual audio sink..."
	@if pactl list sinks short 2>/dev/null | grep -q '\bobs-to-zoom\b'; then \
		echo "  Virtual audio sink already exists"; \
	else \
		pactl load-module module-null-sink sink_name=obs-to-zoom sink_properties=device.description=OBS-to-Zoom channel_map=stereo >/dev/null && \
		echo "  ✓ Created audio sink: obs-to-zoom"; \
		echo "  ✓ Zoom mic will appear as: Monitor of OBS-to-Zoom"; \
	fi
	@$(MAKE) --no-print-directory _virtual-instructions-linux
endif

_virtual-instructions-linux:
	@echo ""
	@echo -e "\033[1;33m╔══════════════════════════════════════════════════════════════╗\033[0m"
	@echo -e "\033[1;33m║            OBS SETTINGS — do these in order                 ║\033[0m"
	@echo -e "\033[1;33m╚══════════════════════════════════════════════════════════════╝\033[0m"
	@echo ""
	@echo -e "\033[1;36m[1] Settings → Audio → Advanced\033[0m"
	@echo    "      Monitoring Device:  OBS-to-Zoom"
	@echo ""
	@echo -e "\033[1;36m[2] Audio Mixer  (for EACH source you want Zoom to hear)\033[0m"
	@echo    "      click the ⚙ gear  →  Advanced Audio Properties"
	@echo -e "      Audio Monitoring:  \033[1;31mMonitor and Output\033[0m   \033[1;31m← easy to miss!\033[0m"
	@echo    "      (default is 'Monitor Off' — that is why you get no audio)"
	@echo ""
	@echo -e "\033[1;36m[3] Controls dock  →  Start Virtual Camera\033[0m"
	@echo ""
	@echo -e "\033[1;33m╔══════════════════════════════════════════════════════════════╗\033[0m"
	@echo -e "\033[1;33m║            ZOOM SETTINGS                                    ║\033[0m"
	@echo -e "\033[1;33m╚══════════════════════════════════════════════════════════════╝\033[0m"
	@echo ""
	@echo -e "\033[1;36m[4] Settings → Video\033[0m"
	@echo    "      Camera:      OBS Virtual Camera"
	@echo ""
	@echo -e "\033[1;36m[5] Settings → Audio\033[0m"
	@echo    "      Microphone:  Monitor of OBS-to-Zoom"
	@echo    "      UNCHECK 'Automatically adjust microphone volume'"
	@echo ""
	@echo -e "\033[1;32mThen run:  make virtual-verify\033[0m   (confirms audio is flowing)"

_virtual-instructions-mac:
	@echo ""
	@echo -e "\033[1;33m╔══════════════════════════════════════════════════════════════╗\033[0m"
	@echo -e "\033[1;33m║            OBS SETTINGS — do these in order                 ║\033[0m"
	@echo -e "\033[1;33m╚══════════════════════════════════════════════════════════════╝\033[0m"
	@echo ""
	@echo -e "\033[1;36m[1] Settings → Audio → Advanced\033[0m"
	@echo    "      Monitoring Device:  BlackHole 2ch"
	@echo ""
	@echo -e "\033[1;36m[2] Audio Mixer  (for EACH source you want Zoom to hear)\033[0m"
	@echo    "      click the ⚙ gear  →  Advanced Audio Properties"
	@echo -e "      Audio Monitoring:  \033[1;31mMonitor and Output\033[0m   \033[1;31m← easy to miss!\033[0m"
	@echo    "      (default is 'Monitor Off' — that is why you get no audio)"
	@echo ""
	@echo -e "\033[1;36m[3] Controls dock  →  Start Virtual Camera\033[0m"
	@echo ""
	@echo -e "\033[1;33m╔══════════════════════════════════════════════════════════════╗\033[0m"
	@echo -e "\033[1;33m║            ZOOM SETTINGS                                    ║\033[0m"
	@echo -e "\033[1;33m╚══════════════════════════════════════════════════════════════╝\033[0m"
	@echo ""
	@echo -e "\033[1;36m[4] Settings → Video\033[0m"
	@echo    "      Camera:      OBS Virtual Camera"
	@echo ""
	@echo -e "\033[1;36m[5] Settings → Audio\033[0m"
	@echo    "      Microphone:  BlackHole 2ch    (real input — no 'Monitor of' prefix)"
	@echo    "      UNCHECK 'Automatically adjust microphone volume'"
	@echo ""
	@echo -e "\033[1;32mThen run:  make virtual-verify\033[0m   (confirms audio is flowing)"

# Verify audio is actually reaching the virtual sink
ifeq ($(PLATFORM),mac)
virtual-verify:
	@echo "=== Verifying Virtual Device Pipeline (macOS) ==="
	@echo ""
	@printf "BlackHole 2ch driver ... "
	@test -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" && echo "✓" || (echo "✗ missing — run: make virtual-install"; exit 1)
	@printf "OBS Studio ............ "
	@test -d "/Applications/OBS.app" && echo "✓" || (echo "✗ missing — run: make virtual-install"; exit 1)
	@echo ""
	@echo "Sampling BlackHole for 3 seconds (play audio through OBS now)..."
	@vol=$$(ffmpeg -hide_banner -f avfoundation -i ":BlackHole 2ch" -t 3 -af volumedetect -f null - 2>&1 | awk -F': ' '/mean_volume/ {print $$2}' | awk '{print $$1}'); \
	if [ -z "$$vol" ] || [ "$$vol" = "-91.0" ] || [ "$$vol" = "-inf" ]; then \
		echo ""; \
		echo "  ✗ NO AUDIO detected on BlackHole 2ch (mean_volume=$$vol)"; \
		echo ""; \
		echo "  Fix in OBS:"; \
		echo "    1. Settings → Audio → Advanced → Monitoring Device = BlackHole 2ch"; \
		echo "    2. Audio Mixer → gear on your source → Advanced Audio Properties"; \
		echo "       → Audio Monitoring = 'Monitor and Output'  (NOT 'Monitor Off')"; \
		echo "    3. Make sure the source is not muted (no red speaker)"; \
		exit 1; \
	else \
		echo "  ✓ Audio flowing (mean_volume: $$vol dB)"; \
		echo "  ✓ Zoom should now hear audio on 'BlackHole 2ch'"; \
	fi
else
virtual-verify:
	@echo "=== Verifying Virtual Device Pipeline ==="
	@echo ""
	@printf "Virtual camera at /dev/video10 ... "
	@test -e /dev/video10 && echo "✓" || (echo "✗ missing — run: make virtual-start"; exit 1)
	@printf "Audio sink 'obs-to-zoom' exists ... "
	@pactl list sinks short 2>/dev/null | grep -q '\bobs-to-zoom\b' && echo "✓" || (echo "✗ missing — run: make virtual-start"; exit 1)
	@echo ""
	@echo "Sampling sink for 3 seconds (play audio through OBS now)..."
	@peak=$$(timeout 3 pactl subscribe >/dev/null 2>&1; \
		parec --device=obs-to-zoom.monitor --raw --format=s16le --rate=48000 --channels=2 2>/dev/null | \
		timeout 3 od -An -td2 -w2 2>/dev/null | awk '{v=$$1<0?-$$1:$$1; if(v>m)m=v} END{print m+0}'); \
	if [ -z "$$peak" ] || [ "$$peak" = "0" ]; then \
		echo ""; \
		echo "  ✗ NO AUDIO detected on obs-to-zoom sink."; \
		echo ""; \
		echo "  Fix in OBS:"; \
		echo "    1. Settings → Audio → Advanced → Monitoring Device = OBS-to-Zoom"; \
		echo "    2. Audio Mixer → gear on your source → Advanced Audio Properties"; \
		echo "       → Audio Monitoring = 'Monitor and Output'  (NOT 'Monitor Off')"; \
		echo "    3. Make sure the source is not muted (no red speaker)"; \
		exit 1; \
	else \
		echo "  ✓ Audio flowing (peak sample: $$peak)"; \
		echo "  ✓ Zoom should now hear audio on 'Monitor of OBS-to-Zoom'"; \
	fi
endif

# Unload virtual camera and remove virtual audio sink
ifeq ($(PLATFORM),mac)
virtual-stop:
	@echo "=== Stopping Virtual Devices (macOS) ==="
	@echo ""
	@echo "Nothing to unload on macOS:"
	@echo "  • Stop Virtual Camera from inside OBS (Controls → Stop Virtual Camera)"
	@echo "  • BlackHole 2ch is a persistent system driver and stays installed"
	@echo "    (uninstall with: brew uninstall blackhole-2ch)"
else
virtual-stop:
	@echo "=== Stopping Virtual Devices ==="
	@echo ""
	@echo "Removing virtual audio..."
	@for module_id in $$(pactl list modules short 2>/dev/null | grep "obs-to-zoom" | awk '{print $$1}'); do \
		pactl unload-module $$module_id 2>/dev/null && echo "  ✓ Unloaded module $$module_id"; \
	done || echo "  No virtual audio modules found"
	@echo ""
	@echo "Unloading virtual camera..."
	@if lsmod | grep -q v4l2loopback; then \
		sudo modprobe -r v4l2loopback && echo "  ✓ Virtual camera unloaded"; \
	else \
		echo "  v4l2loopback not loaded"; \
	fi
	@echo ""
	@echo "=== Virtual devices stopped ==="
endif

# Show status of virtual devices
ifeq ($(PLATFORM),mac)
virtual-status:
	@echo "=== Virtual Device Status (macOS) ==="
	@echo ""
	@echo "Virtual Camera (built into OBS):"
	@if [ -d "/Applications/OBS.app" ]; then \
		echo "  ✓ OBS Studio installed at /Applications/OBS.app"; \
		echo "  Note: 'OBS Virtual Camera' only appears to other apps while OBS is"; \
		echo "        running AND 'Start Virtual Camera' has been clicked."; \
	else \
		echo "  ✗ OBS not installed (run: make virtual-install)"; \
	fi
	@echo ""
	@echo "Virtual Audio (BlackHole 2ch):"
	@if [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]; then \
		echo "  ✓ BlackHole 2ch driver installed"; \
		echo "  ✓ Zoom mic:  'BlackHole 2ch'"; \
	else \
		echo "  ✗ Not installed (run: make virtual-install)"; \
	fi
else
virtual-status:
	@echo "=== Virtual Device Status ==="
	@echo ""
	@echo "Virtual Camera:"
	@if lsmod | grep -q v4l2loopback; then \
		echo "  ✓ v4l2loopback loaded"; \
		v4l2-ctl --list-devices 2>/dev/null | grep -A1 "OBS Virtual Camera" || echo "  Device: /dev/video10"; \
	else \
		echo "  ✗ Not loaded (run: make virtual-start)"; \
	fi
	@echo ""
	@echo "Virtual Audio Sink:"
	@if pactl list sinks short 2>/dev/null | grep -q '\bobs-to-zoom\b'; then \
		echo "  ✓ obs-to-zoom sink active"; \
		echo "  ✓ Zoom mic:  'Monitor of OBS-to-Zoom'"; \
	else \
		echo "  ✗ Not created (run: make virtual-start)"; \
	fi
endif

# ============================================================================
# QUICK START - One command OBS → Zoom
# ============================================================================

ifeq ($(PLATFORM),mac)
obs-to-zoom: virtual-start
	@echo ""
	@echo "=== Launching OBS Studio ==="
	@if [ -d "/Applications/OBS.app" ]; then \
		open -a OBS && echo "  ✓ OBS launched"; \
	else \
		echo "  ✗ OBS not found. Install it first: make virtual-install"; \
		exit 1; \
	fi
	@echo ""
	@$(MAKE) --no-print-directory _virtual-instructions-mac
	@echo ""
	@echo "When done: stop Virtual Camera from inside OBS."
else
obs-to-zoom: virtual-start
	@echo ""
	@echo "=== Launching OBS Studio ==="
	@if command -v obs >/dev/null 2>&1; then \
		obs &disown && echo "  ✓ OBS launched"; \
	elif flatpak list 2>/dev/null | grep -qi obs; then \
		flatpak run com.obsproject.Studio &disown && echo "  ✓ OBS launched (flatpak)"; \
	else \
		echo "  ✗ OBS not found. Install it first: make virtual-install or sudo pacman -S obs-studio"; \
		exit 1; \
	fi
	@echo ""
	@$(MAKE) --no-print-directory _virtual-instructions-linux
	@echo ""
	@echo "Run 'make virtual-stop' when done."
endif

# ============================================================================
# LOCAL TESTING
# ============================================================================

# Send a test pattern over UDP to localhost (no hardware needed)
test-stream:
	@echo "Sending test pattern to udp://127.0.0.1:$(UDP_PORT)..."
	@echo "In OBS: Add Media Source → uncheck 'Local File' → input: udp://@:$(UDP_PORT)"
	@echo "Press Ctrl+C to stop"
	@echo ""
	ffmpeg -re \
		-f lavfi -i testsrc2=size=$(RESOLUTION):rate=$(FRAMERATE) \
		-f lavfi -i sine=frequency=440:sample_rate=$(AUDIO_RATE) \
		-c:v libx264 -preset ultrafast -tune zerolatency -b:v $(VIDEO_BITRATE) \
		-c:a aac -b:a $(AUDIO_BITRATE) -ar $(AUDIO_RATE) \
		-f mpegts "udp://127.0.0.1:$(UDP_PORT)?pkt_size=1316"

# ============================================================================
# STREAMING
# ============================================================================
# OBS receives via Media Source with input: udp://@:5000
# ============================================================================

stream:
	@echo ""
	@echo -e "                                        \033[1;33m┌───┬───┬───┬───┬───┐\033[0m"
	@echo -e "                                        \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[0m"
	@echo -e "            \033[1;37m_____________\033[0m               \033[1;33m├───┼───┼───┼───┼───┤\033[0m"
	@echo -e "           \033[1;37m/             \\\\\033[0m              \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[0m"
	@echo -e "    \033[1;36m┌─────┬───────────────┬─\033[1;31m===========\033[0m─\033[1;33m┴───┴───┴───┴───┴───┘\033[0m"
	@echo -e "    \033[1;36m│\033[1;32m UDP \033[1;36m│\033[1;35m░░░░░░░░░░░░░░░\033[1;36m│\033[1;31m>\033[0m"
	@echo -e "    \033[1;36m└─────┴───────────────┴─\033[1;31m===========\033[0m─\033[1;33m┬───┬───┬───┬───┬───┐\033[0m"
	@echo -e "           \033[1;37m\\_____________/\033[0m              \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[0m"
	@echo -e "                  \033[1;37m│\033[0m                     \033[1;33m├───┼───┼───┼───┼───┤\033[0m"
	@echo -e "                  \033[1;37m│\033[0m                     \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[1;32m ▶ \033[1;33m│\033[0m"
	@echo -e "                 \033[1;37m╱╲\033[0m                     \033[1;33m└───┴───┴───┴───┴───┘\033[0m"
	@echo ""
	@echo -e "         \033[1;31m╦ ╦ ╔╦╗ ╔═╗\033[0m   \033[1;35m╔╗  ╦  ╔═╗ ╔═╗ ╔╦╗ ╔═╗ ╦═╗\033[0m"
	@echo -e "         \033[1;31m║ ║  ║║ ╠═╝\033[0m   \033[1;35m╠╩╗ ║  ╠═╣ ╚═╗  ║  ║╣  ╠╦╝\033[0m"
	@echo -e "         \033[1;31m╚═╝ ═╩╝ ╩\033[0m     \033[1;35m╚═╝ ╩═╝╩ ╩ ╚═╝  ╩  ╚═╝ ╩╚═\033[0m"
	@echo ""
	@echo -e "  \033[1;32mTarget:\033[0m $(TARGET_IP):$(UDP_PORT)"
	@echo -e "  \033[1;32mOBS:\033[0m Add Media Source -> uncheck 'Local File' -> input: \033[1;33mudp://@:$(UDP_PORT)\033[0m"
	@echo -e "  \033[1;37mPress Ctrl+C to stop\033[0m"
	@echo ""
ifeq ($(PLATFORM),mac)
	ffmpeg \
		-f avfoundation -framerate $(FRAMERATE) -video_size $(RESOLUTION) -i "$(VIDEO_DEV):$(AUDIO_DEV)" \
		-c:v libx264 -preset ultrafast -tune zerolatency -b:v $(VIDEO_BITRATE) \
		-c:a aac -b:a $(AUDIO_BITRATE) -ar $(AUDIO_RATE) \
		-f mpegts "udp://$(TARGET_IP):$(UDP_PORT)?pkt_size=1316"
else
	ffmpeg \
		-f v4l2 -framerate $(FRAMERATE) -video_size $(RESOLUTION) -i $(VIDEO_DEV) \
		-f alsa -i $(AUDIO_DEV) \
		-c:v libx264 -preset ultrafast -tune zerolatency -b:v $(VIDEO_BITRATE) \
		-c:a aac -b:a $(AUDIO_BITRATE) -ar $(AUDIO_RATE) \
		-f mpegts "udp://$(TARGET_IP):$(UDP_PORT)?pkt_size=1316"
endif

# Stop any running ffmpeg streams
ifeq ($(PLATFORM),mac)
stop:
	@pkill -f "ffmpeg.*avfoundation" 2>/dev/null && echo "Stopped stream" || echo "No stream running"
else
stop:
	@pkill -f "ffmpeg.*$(VIDEO_DEV)" 2>/dev/null && echo "Stopped stream" || echo "No stream running"
endif
