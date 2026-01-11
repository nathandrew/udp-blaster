# Church Video Streaming - Razer Ripsaw HD to OBS via network
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

# Streaming ports
UDP_PORT ?= 5000
RTMP_PORT ?= 1935

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

.PHONY: help setup detect find-pi my-ip ssh-pi test-video test-audio test-receive stream-udp stream-rtmp stop

help:
	@echo "Church Video Streaming Commands"
	@echo "================================"
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
	@echo "  make stream-udp  - Stream via UDP (low latency)"
	@echo "  make stream-rtmp - Stream via RTMP (more reliable)"
	@echo "  make stop        - Stop any running streams"
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
	@ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1 || echo "No network connection found"
	@echo ""
	@echo "Tell the streaming machine to use:"
	@echo "  make stream-udp TARGET_IP=$$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1)"

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
	ffmpeg -f alsa -i $(AUDIO_DEV) -af "volumedetect" -f null - 2>&1 | grep -E "mean_volume|max_volume" || \
		arecord -D $(AUDIO_DEV) -vvv -f cd /dev/null

# Receive and display UDP stream (run on receiving machine to test)
test-receive:
	@echo "Opening VLC to receive UDP stream on port $(UDP_PORT)..."
	@echo "Run 'make stream-udp' on the Pi first!"
	@echo ""
	vlc udp://@:$(UDP_PORT)

# ============================================================================
# UDP STREAMING (Recommended - Lower latency)
# ============================================================================
# OBS receives via Media Source with input: udp://@:5000
# ============================================================================

stream-udp:
	@echo "Starting UDP stream to $(TARGET_IP):$(UDP_PORT)"
	@echo "In OBS: Add Media Source -> uncheck 'Local File' -> input: udp://@:$(UDP_PORT)"
	@echo "Press Ctrl+C to stop"
	@echo ""
	ffmpeg \
		-f v4l2 -framerate $(FRAMERATE) -video_size $(RESOLUTION) -i $(VIDEO_DEV) \
		-f alsa -i $(AUDIO_DEV) \
		-c:v libx264 -preset ultrafast -tune zerolatency -b:v $(VIDEO_BITRATE) \
		-c:a aac -b:a $(AUDIO_BITRATE) -ar $(AUDIO_RATE) \
		-f mpegts "udp://$(TARGET_IP):$(UDP_PORT)?pkt_size=1316"

# ============================================================================
# RTMP STREAMING (Alternative - More reliable, higher latency)
# ============================================================================
# Requires RTMP server on target. OBS receives via Media Source with
# input: rtmp://localhost/live/stream
# ============================================================================

stream-rtmp:
	@echo "Starting RTMP stream to rtmp://$(TARGET_IP):$(RTMP_PORT)/live/stream"
	@echo "Target must be running an RTMP server (see README)"
	@echo "In OBS: Add Media Source -> input: rtmp://localhost/live/stream"
	@echo "Press Ctrl+C to stop"
	@echo ""
	ffmpeg \
		-f v4l2 -framerate $(FRAMERATE) -video_size $(RESOLUTION) -i $(VIDEO_DEV) \
		-f alsa -i $(AUDIO_DEV) \
		-c:v libx264 -preset ultrafast -tune zerolatency -b:v $(VIDEO_BITRATE) \
		-c:a aac -b:a $(AUDIO_BITRATE) -ar $(AUDIO_RATE) \
		-f flv "rtmp://$(TARGET_IP):$(RTMP_PORT)/live/stream"

# Stop any running ffmpeg streams
stop:
	@pkill -f "ffmpeg.*$(VIDEO_DEV)" 2>/dev/null && echo "Stopped stream" || echo "No stream running"
