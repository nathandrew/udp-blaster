#!/bin/bash
# Interactive setup script for UDP Blaster

echo "=== UDP Blaster Setup ==="
echo ""

OS="$(uname -s)"

# ============================================================================
# DEVICE SELECTION
# ============================================================================

if [ "$OS" = "Darwin" ]; then
    # --- macOS: enumerate avfoundation devices via ffmpeg ---
    echo "Detecting AVFoundation devices (macOS)..."
    echo ""

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo "ffmpeg not installed. Run: brew install ffmpeg"
        exit 1
    fi

    # ffmpeg prints device list to stderr in this format:
    #   [AVFoundation indev @ 0x...] AVFoundation video devices:
    #   [AVFoundation indev @ 0x...] [0] FaceTime HD Camera
    #   [AVFoundation indev @ 0x...] [1] Capture screen 0
    #   [AVFoundation indev @ 0x...] AVFoundation audio devices:
    #   [AVFoundation indev @ 0x...] [0] BlackHole 2ch
    #   [AVFoundation indev @ 0x...] [1] MacBook Pro Microphone
    raw=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1)

    # Split into video and audio sections
    video_section=$(echo "$raw" | awk '/AVFoundation video devices:/,/AVFoundation audio devices:/' | grep -E '\[[0-9]+\]')
    audio_section=$(echo "$raw" | awk '/AVFoundation audio devices:/,0' | grep -E '\[[0-9]+\]')

    mapfile -t video_indices < <(echo "$video_section" | sed -E 's/.*\[([0-9]+)\].*/\1/')
    mapfile -t video_names   < <(echo "$video_section" | sed -E 's/.*\[[0-9]+\] //')
    mapfile -t audio_indices < <(echo "$audio_section" | sed -E 's/.*\[([0-9]+)\].*/\1/')
    mapfile -t audio_names   < <(echo "$audio_section" | sed -E 's/.*\[[0-9]+\] //')

    if [ ${#video_indices[@]} -eq 0 ]; then
        echo "No video devices found. Grant ffmpeg camera permission in System Settings → Privacy & Security → Camera."
        exit 1
    fi

    echo "SELECT VIDEO DEVICE:"
    echo "--------------------"
    for i in "${!video_indices[@]}"; do
        echo "  $((i+1))) [${video_indices[$i]}] ${video_names[$i]}"
    done
    echo ""
    read -p "Enter number [1-${#video_indices[@]}]: " video_choice
    if [[ "$video_choice" -lt 1 || "$video_choice" -gt ${#video_indices[@]} ]]; then
        echo "Invalid selection"; exit 1
    fi
    selected_video="${video_indices[$((video_choice-1))]}"
    echo "Selected: $selected_video (${video_names[$((video_choice-1))]})"
    echo ""

    if [ ${#audio_indices[@]} -eq 0 ]; then
        echo "No audio devices found. Grant ffmpeg microphone permission in System Settings → Privacy & Security → Microphone."
        exit 1
    fi

    echo "SELECT AUDIO DEVICE:"
    echo "--------------------"
    for i in "${!audio_indices[@]}"; do
        echo "  $((i+1))) [${audio_indices[$i]}] ${audio_names[$i]}"
    done
    echo ""
    read -p "Enter number [1-${#audio_indices[@]}]: " audio_choice
    if [[ "$audio_choice" -lt 1 || "$audio_choice" -gt ${#audio_indices[@]} ]]; then
        echo "Invalid selection"; exit 1
    fi
    selected_audio="${audio_indices[$((audio_choice-1))]}"
    echo "Selected: $selected_audio (${audio_names[$((audio_choice-1))]})"
    echo ""

else
    # --- Linux: enumerate via v4l2-ctl + arecord ---
    echo "Detecting video devices..."
    echo ""

    mapfile -t video_devices < <(v4l2-ctl --list-devices 2>/dev/null | grep -E "^\s+/dev/video[0-9]+$" | awk 'NR % 2 == 1' | tr -d '\t')
    mapfile -t video_names < <(v4l2-ctl --list-devices 2>/dev/null | grep -v "^\s" | sed 's/(.*//' | grep -v '^[[:space:]]*$')

    if [ ${#video_devices[@]} -eq 0 ]; then
        echo "No video devices found. Is v4l-utils installed?"
        exit 1
    fi

    echo "SELECT VIDEO DEVICE:"
    echo "--------------------"
    for i in "${!video_devices[@]}"; do
        echo "  $((i+1))) ${video_devices[$i]} - ${video_names[$i]}"
    done
    echo ""
    read -p "Enter number [1-${#video_devices[@]}]: " video_choice

    if [[ "$video_choice" -lt 1 || "$video_choice" -gt ${#video_devices[@]} ]]; then
        echo "Invalid selection"
        exit 1
    fi
    selected_video="${video_devices[$((video_choice-1))]}"
    echo "Selected: $selected_video"
    echo ""

    echo "Detecting audio devices..."
    echo ""

    mapfile -t audio_cards < <(arecord -l 2>/dev/null | grep "^card" | sed 's/:.*//' | awk '{print $2}')
    mapfile -t audio_names < <(arecord -l 2>/dev/null | grep "^card" | sed 's/^[^:]*\[//' | sed 's/\].*$//')

    if [ ${#audio_cards[@]} -eq 0 ]; then
        echo "No audio devices found. Is alsa-utils installed?"
        exit 1
    fi

    echo "SELECT AUDIO DEVICE:"
    echo "--------------------"
    for i in "${!audio_cards[@]}"; do
        echo "  $((i+1))) hw:${audio_cards[$i]},0 - ${audio_names[$i]}"
    done
    echo ""
    read -p "Enter number [1-${#audio_cards[@]}]: " audio_choice

    if [[ "$audio_choice" -lt 1 || "$audio_choice" -gt ${#audio_cards[@]} ]]; then
        echo "Invalid selection"
        exit 1
    fi
    selected_audio="hw:${audio_cards[$((audio_choice-1))]},0"
    echo "Selected: $selected_audio"
    echo ""
fi

# ============================================================================
# TARGET IP
# ============================================================================

echo "TARGET IP (OBS Machine):"
echo "------------------------"

echo "  1) Enter manually"
echo "  2) This machine (localhost/127.0.0.1)"

# Detect local IP and offer a network scan option
if [ "$OS" = "Darwin" ]; then
    local_ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
else
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+')
fi

if [ -n "$local_ip" ]; then
    network_prefix=$(echo "$local_ip" | sed 's/\.[0-9]*$/./')
    echo "  3) Scan network ${network_prefix}0/24 (slow)"
fi
echo ""
read -p "Enter choice: " ip_choice

case "$ip_choice" in
    1)
        read -p "Enter target IP address: " selected_ip
        ;;
    2)
        selected_ip="127.0.0.1"
        ;;
    3)
        echo "Scanning network (this may take 10-20 seconds)..."
        echo "Active hosts:"
        nmap -sn "${network_prefix}0/24" 2>/dev/null | grep "Nmap scan" | sed 's/Nmap scan report for /  /'
        echo ""
        read -p "Enter target IP address: " selected_ip
        ;;
    *)
        echo "Invalid selection"
        exit 1
        ;;
esac
echo "Selected: $selected_ip"
echo ""

# ============================================================================
# SAVE CONFIG
# ============================================================================

echo "# UDP Blaster Config" > .config.mk
echo "# Generated by 'make setup' on $(date)" >> .config.mk
echo "" >> .config.mk
echo "VIDEO_DEV = $selected_video" >> .config.mk
echo "AUDIO_DEV = $selected_audio" >> .config.mk
echo "TARGET_IP = $selected_ip" >> .config.mk

echo "=== UDP Blaster configuration saved to .config.mk ==="
echo ""
cat .config.mk
echo ""
echo "Next steps:"
echo "  make test-video   - Test video capture"
echo "  make test-audio   - Test audio levels"
echo "  make stream       - Start streaming to OBS"
