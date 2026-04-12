# UDP Blaster - Razer Ripsaw HD to OBS via network
#
# Usage: make <target>
# Run 'make help' to see available commands

# ============================================================================
# CONFIGURATION - Load saved config if exists, otherwise use defaults
# ============================================================================

-include .config.mk

# Video capture device (run 'make detect' to find yours)
VIDEO_DEV ?= /dev/video0

# Audio capture device (run 'make detect' to find yours)
AUDIO_DEV ?= hw:0,0

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
       virtual-check virtual-install virtual-start virtual-stop virtual-status test-stream obs-to-zoom

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
	@echo "  make virtual-install - Install virtual device dependencies (Arch Linux)"
	@echo "  make virtual-start   - Load virtual camera + create virtual audio sink"
	@echo "  make virtual-stop    - Unload virtual camera + remove virtual audio sink"
	@echo "  make virtual-status  - Show status of virtual devices"
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
	@echo "Override with: make stream-udp TARGET_IP=192.168.1.50"

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
detect:
	@echo "=== Video Devices ==="
	@v4l2-ctl --list-devices 2>/dev/null || echo "Install v4l-utils: sudo pacman -S v4l-utils"
	@echo ""
	@echo "=== Audio Devices ==="
	@arecord -l 2>/dev/null || echo "Install alsa-utils: sudo pacman -S alsa-utils"
	@echo ""
	@echo "=== Device Formats ($(VIDEO_DEV)) ==="
	@v4l2-ctl -d $(VIDEO_DEV) --list-formats-ext 2>/dev/null | head -30 || echo "Device not found"

# Preview video locally
test-video:
	@echo "Opening preview window... Press Q to quit"
	ffplay -f v4l2 -framerate $(FRAMERATE) -video_size $(RESOLUTION) $(VIDEO_DEV)

# Test audio levels
test-audio:
	@echo "Monitoring audio levels... Press Ctrl+C to stop"
	@echo "You should see meter movement when there's sound"
	@echo ""
	arecord -D $(AUDIO_DEV) -vvv -f cd -c 2 -r 48000 /dev/null 2>&1

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

# Install virtual device dependencies (Arch Linux)
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

# Load virtual camera and create virtual audio sink
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
	@if pactl list sinks short 2>/dev/null | grep -q obs-to-zoom; then \
		echo "  Virtual audio sink already exists"; \
	else \
		pactl load-module module-null-sink media.class=Audio/Sink sink_name=obs-to-zoom channel_map=stereo >/dev/null && \
		echo "  ✓ Created audio sink: obs-to-zoom"; \
	fi
	@if pactl list sources short 2>/dev/null | grep -q obs-to-zoom-source; then \
		echo "  Virtual audio source already exists"; \
	else \
		pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=obs-to-zoom-source channel_map=stereo >/dev/null && \
		echo "  ✓ Created audio source: obs-to-zoom-source"; \
	fi
	@echo ""
	@echo "Linking audio sink to source..."
	@sleep 0.5
	@pw-link "obs-to-zoom:monitor_FL" "obs-to-zoom-source:input_FL" 2>/dev/null && echo "  ✓ Linked FL channel" || echo "  Already linked or pw-link unavailable"
	@pw-link "obs-to-zoom:monitor_FR" "obs-to-zoom-source:input_FR" 2>/dev/null && echo "  ✓ Linked FR channel" || echo "  Already linked or pw-link unavailable"
	@echo ""
	@echo "=== Virtual devices ready ==="
	@echo "Next steps:"
	@echo "  1. In OBS: Start Virtual Camera"
	@echo "  2. In OBS: Settings → Audio → Monitoring Device → obs-to-zoom"
	@echo "  3. In OBS: Audio Mixer → gear → Advanced Audio → Monitor and Output"
	@echo "  4. In Zoom: Select 'OBS Virtual Camera' for video"
	@echo "  5. In Zoom: Select 'obs-to-zoom-source' for microphone"

# Unload virtual camera and remove virtual audio sink
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

# Show status of virtual devices
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
	@if pactl list sinks short 2>/dev/null | grep -q obs-to-zoom; then \
		echo "  ✓ obs-to-zoom sink active"; \
	else \
		echo "  ✗ Not created (run: make virtual-start)"; \
	fi
	@echo ""
	@echo "Virtual Audio Source (Zoom mic):"
	@if pactl list sources short 2>/dev/null | grep -q obs-to-zoom-source; then \
		echo "  ✓ obs-to-zoom-source active"; \
	else \
		echo "  ✗ Not created (run: make virtual-start)"; \
	fi
	@echo ""
	@echo "PipeWire Links:"
	@pw-link -l 2>/dev/null | grep -A2 "obs-to-zoom" || echo "  No links found"

# ============================================================================
# QUICK START - One command OBS → Zoom
# ============================================================================

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
	@echo "=== All set! ==="
	@echo ""
	@echo "In OBS:"
	@echo "  1. Start Virtual Camera (Controls dock → Start Virtual Camera)"
	@echo "  2. Settings → Audio → Monitoring Device → obs-to-zoom"
	@echo "  3. Audio Mixer → gear → Advanced Audio → set Monitor and Output"
	@echo ""
	@echo "In Zoom:"
	@echo "  4. Video: select 'OBS Virtual Camera'"
	@echo "  5. Mic:   select 'obs-to-zoom-source'"
	@echo ""
	@echo "Run 'make virtual-stop' when done."

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
	ffmpeg \
		-f v4l2 -framerate $(FRAMERATE) -video_size $(RESOLUTION) -i $(VIDEO_DEV) \
		-f alsa -i $(AUDIO_DEV) \
		-c:v libx264 -preset ultrafast -tune zerolatency -b:v $(VIDEO_BITRATE) \
		-c:a aac -b:a $(AUDIO_BITRATE) -ar $(AUDIO_RATE) \
		-f mpegts "udp://$(TARGET_IP):$(UDP_PORT)?pkt_size=1316"

# Stop any running ffmpeg streams
stop:
	@pkill -f "ffmpeg.*$(VIDEO_DEV)" 2>/dev/null && echo "Stopped stream" || echo "No stream running"
