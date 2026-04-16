# PuckPro

Browser-based hockey shot analysis using MediaPipe pose detection and Claude Vision.

## What It Is

PuckPro runs Google's MediaPipe pose detection model as WASM directly in the browser at 30 frames per second, tracking 33 body landmarks (shoulders, elbows, wrists, hips, knees, ankles) plus a virtual stick position estimated from hand placement. A shot detection algorithm validates shots across a 4-frame temporal window — wind-up, downswing, follow-through, completion — filtering false positives from normal movement.

Only structured shot events (~200 bytes each) cross the wire from the browser to the Phoenix LiveView backend. No video upload, no streaming frames to a server. When a session completes, captured key frames are sent to Claude Vision for analysis with age-aware, hockey-specific coaching prompts that evaluate weight transfer, stick angle, release point, and follow-through mechanics.

The motivation is straightforward: private shooting coaches charge $150/hr and are unavailable to most youth players. This puts real-time biomechanical feedback in a browser tab with a webcam.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Browser                           │
│                                                     │
│  Webcam ─► MediaPipe WASM (30fps)                   │
│            │                                        │
│            ├─► 33 landmarks per frame               │
│            ├─► Shot detection (4-frame validation)   │
│            └─► Structured events (~200 bytes)        │
│                     │                               │
└─────────────────────┼───────────────────────────────┘
                      │ LiveView Hook (WebSocket)
                      ▼
┌─────────────────────────────────────────────────────┐
│                 Phoenix Server                       │
│                                                     │
│  LiveView ─► Session tracking                       │
│           ─► Shot aggregation                       │
│           ─► Claude Vision API (post-session)       │
│           ─► Gamification (XP, levels, streaks)     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

Key design decision: ML runs entirely client-side. The server never sees video data. This avoids upload latency, reduces server costs to near zero, and keeps the privacy story simple — frames stay on device unless explicitly sent for Claude analysis.

The gamification layer (XP progression, level unlocks, session streaks) is modeled after Duolingo's retention mechanics. Kids need a reason to come back.

## Why This Matters

The technical insight is that modern browser ML runtimes (MediaPipe WASM, TensorFlow.js) are fast enough for real-time sports biomechanics without server-side GPU infrastructure. The 200-byte event bridge between client-side ML and server-side LiveView is the architecture that makes this practical: full pose detection in the browser, structured data over the wire, expensive LLM analysis only on key frames after the session.

The long-term direction is ice surface projection — overlaying coaching cues directly onto the rink during practice via a mounted projector. The browser-based detection pipeline is the foundation for that.

## Status

Prototype. Shot detection works. Claude Vision analysis produces useful coaching output. Gamification layer is functional. Not yet deployed for public use.

## Stack

- **Backend:** Elixir, Phoenix LiveView
- **Pose detection:** Google MediaPipe (WASM, in-browser)
- **AI analysis:** Claude Vision API
- **Frontend:** LiveView hooks, Tailwind CSS
- **Shot detection:** Custom 4-frame temporal validation algorithm
