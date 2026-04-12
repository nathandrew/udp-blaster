# Testing Without Hardware

You can exercise the entire OBS → Zoom pipeline without a Razer Ripsaw HD, without a Raspberry Pi, and without a UDP stream from another machine. Useful for debugging the receiver-side virtual-device setup, demoing the project, or running on a laptop in a coffee shop.

The options below are roughly ordered cheapest → most realistic.

---

## Option 1: `make test-stream` (most realistic)

The Makefile includes a one-shot test that sends an ffmpeg-generated color-bars + 440 Hz sine pattern over UDP to localhost. This exercises the **exact same pipeline** as a real Pi stream — same encoder, same MPEG-TS container, same UDP receive path.

**Terminal 1:**
```bash
make test-stream
```

**OBS:**
1. Add Source → **Media Source**
2. Uncheck "Local File"
3. Input: `udp://@:5000`
4. Check "Restart playback when source becomes active"

You should see color bars and hear a sine tone. From here you can configure the virtual camera + microphone and test in Zoom exactly as you would with real hardware.

> This is the best end-to-end test because it validates that OBS is correctly receiving and decoding the UDP stream — not just that some video is showing up in OBS.

---

## Option 2: Play a sample video in OBS

If you don't even need the UDP layer, just give OBS a video to play.

```bash
# Generate a 60-second test pattern with audio (no download needed)
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=440:sample_rate=48000 \
       -t 60 -c:v libx264 -c:a aac ~/test-pattern.mp4
```

Or download a real sample:
```bash
curl -L -o ~/sample-video.mp4 \
  "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4"
```

In OBS:
1. **+** under Sources → **Media Source**
2. Check **Local File**, browse to the file
3. Check **Loop**

Start the Virtual Camera and test in Zoom.

---

## Option 3: Webcam as a Ripsaw stand-in

If you just want any video signal in OBS for testing:

1. Add Source → **Video Capture Device**
2. Pick your built-in webcam
3. Done

Useful for verifying that the OBS → Zoom virtual camera path works on your machine before you go buy capture hardware.

---

## Option 4: Screen / window capture

Even less ceremony:

1. Add Source → **Screen Capture** or **Window Capture**
2. Pick a screen or window
3. Start Virtual Camera

This is the fastest way to confirm Zoom is actually picking up *something* from OBS.

---

## Option 5: VLC window capture

If you want some content but want to control playback:

1. Open any video in VLC
2. In OBS, add a **Window Capture** source
3. Select the VLC window

Combine with Option 4's audio routing if you need sound.

---

## Verifying the audio path independently of Zoom

You don't need to launch Zoom to confirm OBS audio is reaching the virtual sink. Just run:

```bash
make virtual-verify
```

while OBS is playing audio through any source. It samples the sink for 3 seconds and reports whether audio is actually flowing — and if not, prints the exact OBS setting to fix. See [`obs-zoom-linux.md`](obs-zoom-linux.md) or [`obs-zoom-macos.md`](obs-zoom-macos.md) for what's happening under the hood.

---

## Suggested test sequence for a fresh setup

1. `make virtual-install`
2. `make virtual-start`
3. Configure OBS Monitoring Device + per-source "Monitor and Output" — see the OBS-Zoom guides
4. `make test-stream` in one terminal, Media Source `udp://@:5000` in OBS
5. `make virtual-verify` — confirms audio is reaching the sink
6. Open Zoom, pick `OBS Virtual Camera` and the virtual mic
7. Use Zoom's Settings → Video / Audio panels to confirm both sides are alive *before* joining a real call
