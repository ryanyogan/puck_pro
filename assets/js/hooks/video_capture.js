/**
 * VideoCapture Hook
 *
 * Handles camera access and video streaming via MediaRecorder API.
 * Uses MediaPipe Pose for client-side shot detection at 30fps.
 * Optionally streams video chunks to Phoenix LiveView for upload to R2.
 */
import { PoseDetector, LANDMARKS } from './pose_detection';
import { PuckDetector } from './object_detection';

export const VideoCapture = {
  mounted() {
    this.stream = null;
    this.recorder = null;
    this.isRecording = false;
    this.chunkCount = 0;

    // MediaPipe Pose Detection
    this.poseDetector = null;
    this.animationFrameId = null;
    this.devMode = false;

    // Puck Detection (optional)
    this.puckDetector = null;

    // Current detection state for drawing
    this.currentStick = null;
    this.currentPuck = null;

    // Dev mode overlay canvas - get from DOM
    this.overlayCanvas = this.el.querySelector('#detection-overlay');
    this.overlayCtx = this.overlayCanvas ? this.overlayCanvas.getContext('2d') : null;
    console.log('[VideoCapture] Overlay canvas:', this.overlayCanvas ? 'found' : 'not found');

    // Hide canvas initially (dev mode starts off)
    if (this.overlayCanvas) {
      this.overlayCanvas.style.display = 'none';
    }

    // Get video element for preview
    this.videoEl = this.el.querySelector('video');

    // Handle server events
    this.handleEvent("start_recording", async (payload) => {
      const recordVideo = payload.record_video !== false;
      console.log(`[VideoCapture] Received start_recording event, record_video=${recordVideo}`);
      await this.startRecording(recordVideo);
    });

    this.handleEvent("stop_recording", () => {
      console.log("[VideoCapture] Received stop_recording event from server");
      this.stopRecording();
    });

    // Handle dev mode toggle
    this.handleEvent("dev_mode_changed", (payload) => {
      console.log('[VideoCapture] Dev mode changed:', payload.enabled);
      this.devMode = payload.enabled;
      if (this.overlayCanvas) {
        this.overlayCanvas.style.display = payload.enabled ? 'block' : 'none';
        console.log('[VideoCapture] Canvas display:', this.overlayCanvas.style.display, 'size:', this.overlayCanvas.width, 'x', this.overlayCanvas.height);
        if (payload.enabled) {
          // Force resize when dev mode is enabled
          this.resizeOverlay();
        } else {
          // Clear canvas when dev mode disabled
          this.overlayCtx?.clearRect(0, 0, this.overlayCanvas.width, this.overlayCanvas.height);
        }
      }
    });

    // Check camera permission on mount
    this.checkCameraPermission();

    // Set up video resize observer
    this.setupResizeObserver();
  },

  setupResizeObserver() {
    if (!this.videoEl) return;

    // Resize overlay when video loads
    this.videoEl.addEventListener('loadedmetadata', () => {
      console.log('[VideoCapture] Video loadedmetadata, resizing overlay');
      this.resizeOverlay();
    });

    // Also resize on window resize
    window.addEventListener('resize', () => {
      this.resizeOverlay();
    });
  },

  async checkCameraPermission() {
    try {
      const result = await navigator.permissions.query({ name: 'camera' });
      this.pushEvent("camera_permission", { status: result.state });

      result.addEventListener('change', () => {
        this.pushEvent("camera_permission", { status: result.state });
      });
    } catch (err) {
      // Some browsers don't support permission query for camera
      console.log("Camera permission query not supported");
    }
  },

  async startRecording(recordVideo = true) {
    console.log(`[VideoCapture] startRecording(recordVideo=${recordVideo}) called`);
    this.recordingVideo = recordVideo;

    try {
      // Request camera access with constraints optimized for mobile
      console.log("[VideoCapture] Requesting camera access...");
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: "environment" },  // Back camera on mobile
          width: { ideal: 1920, max: 1920 },
          height: { ideal: 1080, max: 1080 },
          frameRate: { ideal: 30, max: 30 }
        },
        audio: false
      });

      // Show live preview
      if (this.videoEl) {
        this.videoEl.srcObject = this.stream;
        this.videoEl.play().catch(console.error);
      }

      const width = this.stream.getVideoTracks()[0]?.getSettings()?.width || 1920;
      const height = this.stream.getVideoTracks()[0]?.getSettings()?.height || 1080;

      // Only set up MediaRecorder if we're actually recording video for AI analysis
      if (recordVideo) {
        const mimeType = this.getBestMimeType();

        if (!mimeType) {
          throw new Error("No supported video format found");
        }

        // Create MediaRecorder with chunked output
        this.recorder = new MediaRecorder(this.stream, {
          mimeType,
          videoBitsPerSecond: 2500000  // 2.5 Mbps for good quality
        });

        // Handle data chunks
        this.recorder.ondataavailable = async (event) => {
          console.log(`[VideoCapture] ondataavailable fired, size: ${event.data.size}`);
          if (event.data.size > 0) {
            this.chunkCount++;
            await this.uploadChunk(event.data);
          }
        };

        // Handle recording errors
        this.recorder.onerror = (event) => {
          console.error("MediaRecorder error:", event.error);
          this.pushEvent("recording_error", { message: event.error?.message || "Recording error" });
        };

        this.recorder.onstop = () => {
          this.pushEvent("recording_stopped", { chunks: this.chunkCount });
        };

        // Start recording with 5-second chunks
        this.recorder.start(5000);
        this.chunkCount = 0;
        console.log(`[VideoCapture] Video recording started! mimeType: ${mimeType}, resolution: ${width}x${height}`);
      } else {
        console.log(`[VideoCapture] Camera preview only (no video recording), resolution: ${width}x${height}`);
      }

      this.isRecording = true;

      // Initialize MediaPipe Pose detection
      await this.initializePoseDetection();

      this.pushEvent("recording_started", {
        mimeType: recordVideo ? this.getBestMimeType() : null,
        width,
        height,
        recordingVideo: recordVideo
      });

    } catch (err) {
      console.error("Camera access error:", err);
      this.pushEvent("camera_error", {
        message: err.message,
        name: err.name
      });
    }
  },

  /**
   * Initialize MediaPipe Pose detection and optional puck detection
   */
  async initializePoseDetection() {
    console.log('[VideoCapture] Initializing MediaPipe Pose...');

    this.poseDetector = new PoseDetector({
      historySize: 15,
      shotCooldownMs: 1000,

      onReady: () => {
        console.log('[VideoCapture] MediaPipe Pose ready');
        this.pushEvent("pose_tracker_ready", {});
      },

      onPoseDetected: (pose, result) => {
        // Update dev mode overlay with skeleton
        if (this.devMode) {
          if (result.landmarks && result.landmarks[0]) {
            this.drawPoseSkeleton(result.landmarks[0]);
          } else {
            // Clear overlay if no pose detected
            if (this.overlayCtx) {
              this.overlayCtx.clearRect(0, 0, this.overlayCanvas.width, this.overlayCanvas.height);
            }
          }
        }
      },

      onStickDetected: (stickData) => {
        // Store current stick for drawing
        this.currentStick = stickData;
      },

      onShotDetected: (shotData) => {
        console.log('[VideoCapture] Shot detected!', shotData);

        // Send shot event to server (only ~200 bytes vs 30KB frames)
        this.pushEvent("shot_detected", {
          timestamp: shotData.timestamp,
          velocity: shotData.velocity,
          shoulder_rotation: shotData.analysis.shoulderRotation,
          hip_rotation: shotData.analysis.hipRotation,
          follow_through: shotData.analysis.followThrough,
          weight_transfer: shotData.analysis.weightTransfer,
          knee_bend: shotData.analysis.kneeBend,
        });
      },

      onError: (error) => {
        console.error('[VideoCapture] MediaPipe error:', error);
        // Fall back to manual tracking if MediaPipe fails
        this.pushEvent("pose_tracker_error", { message: error.message });
      }
    });

    try {
      await this.poseDetector.initialize();
      this.startPoseDetectionLoop();
    } catch (error) {
      console.error('[VideoCapture] Failed to initialize MediaPipe:', error);
      // Continue without pose detection - manual buttons still work
    }

    // Initialize puck detector (optional - don't fail if it doesn't work)
    console.log('[VideoCapture] Initializing Puck Detection...');
    this.puckDetector = new PuckDetector({
      onReady: () => {
        console.log('[VideoCapture] Puck detector ready');
      },
      onPuckDetected: (puckData) => {
        this.currentPuck = puckData;
      },
      onError: (error) => {
        console.warn('[VideoCapture] Puck detection unavailable:', error.message);
        // Continue without puck detection - it's optional
      }
    });

    try {
      await this.puckDetector.initialize();
    } catch (e) {
      console.warn('[VideoCapture] Puck detection disabled:', e.message);
    }
  },

  /**
   * Start the pose detection loop using requestAnimationFrame
   */
  startPoseDetectionLoop() {
    const detectFrame = () => {
      if (!this.videoEl || this.videoEl.readyState < 2) {
        // Video not ready yet, try again
        this.animationFrameId = requestAnimationFrame(detectFrame);
        return;
      }

      const timestamp = performance.now();

      // Run pose detection (includes stick estimation)
      if (this.poseDetector && this.poseDetector.isReady) {
        this.poseDetector.detectPose(this.videoEl, timestamp);
      }

      // Run puck detection (if available)
      // Pass player bounding box so we can exclude it from puck search
      if (this.puckDetector && this.puckDetector.isReady) {
        const playerBox = this.poseDetector?.getPlayerBoundingBox() || null;
        this.puckDetector.detect(this.videoEl, timestamp, playerBox);
      }

      this.animationFrameId = requestAnimationFrame(detectFrame);
    };

    this.animationFrameId = requestAnimationFrame(detectFrame);
    console.log('[VideoCapture] Detection loop started');
  },

  /**
   * Stop the pose detection loop
   */
  stopPoseDetectionLoop() {
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId);
      this.animationFrameId = null;
    }
  },

  /**
   * Draw pose skeleton on overlay canvas (dev mode)
   */
  drawPoseSkeleton(landmarks) {
    if (!this.overlayCtx || !landmarks) return;

    // Ensure proper size
    this.resizeOverlay();

    const ctx = this.overlayCtx;
    const width = this.overlayCanvas.width;
    const height = this.overlayCanvas.height;

    // Clear previous drawing
    ctx.clearRect(0, 0, width, height);

    // Draw dev mode frame
    ctx.strokeStyle = 'rgba(34, 197, 94, 0.5)';
    ctx.lineWidth = 2;
    ctx.setLineDash([10, 5]);
    ctx.strokeRect(10, 10, width - 20, height - 20);
    ctx.setLineDash([]);

    // Draw player bounding box
    if (this.poseDetector) {
      const bbox = this.poseDetector.getPlayerBoundingBox();
      if (bbox) {
        ctx.strokeStyle = '#22c55e'; // Green
        ctx.lineWidth = 3;
        ctx.strokeRect(
          bbox.x * width,
          bbox.y * height,
          bbox.width * width,
          bbox.height * height
        );

        // Label the bounding box
        ctx.fillStyle = '#22c55e';
        ctx.font = 'bold 12px sans-serif';
        const confidence = this.poseDetector.getDetectionConfidence();
        ctx.fillText(`Player (${Math.round(confidence * 100)}%)`, bbox.x * width + 5, bbox.y * height - 5);
      }
    }

    // Skeleton connections
    const connections = [
      // Torso
      [11, 12], [11, 23], [12, 24], [23, 24],
      // Left arm
      [11, 13], [13, 15],
      // Right arm
      [12, 14], [14, 16],
      // Left leg
      [23, 25], [25, 27],
      // Right leg
      [24, 26], [26, 28],
      // Head to shoulders
      [11, 0], [12, 0],
    ];

    // Draw connections (skeleton lines)
    ctx.strokeStyle = '#22c55e'; // Green
    ctx.lineWidth = 3;

    connections.forEach(([startIdx, endIdx]) => {
      const p1 = landmarks[startIdx];
      const p2 = landmarks[endIdx];
      if (p1 && p2 && p1.visibility > 0.5 && p2.visibility > 0.5) {
        ctx.beginPath();
        ctx.moveTo(p1.x * width, p1.y * height);
        ctx.lineTo(p2.x * width, p2.y * height);
        ctx.stroke();
      }
    });

    // Draw wrists highlighted (key for shot detection)
    const wristIndices = [15, 16]; // Left wrist, Right wrist
    wristIndices.forEach(idx => {
      const p = landmarks[idx];
      if (p && p.visibility > 0.5) {
        ctx.fillStyle = '#ef4444'; // Red for wrists
        ctx.beginPath();
        ctx.arc(p.x * width, p.y * height, 10, 0, 2 * Math.PI);
        ctx.fill();

        // Add label
        ctx.fillStyle = '#ffffff';
        ctx.font = 'bold 10px sans-serif';
        ctx.fillText(idx === 15 ? 'L' : 'R', p.x * width - 4, p.y * height + 4);
      }
    });

    // Draw other key landmarks
    const keyLandmarks = [
      { idx: 11, color: '#3b82f6', label: 'LS' }, // Left shoulder
      { idx: 12, color: '#3b82f6', label: 'RS' }, // Right shoulder
      { idx: 23, color: '#8b5cf6', label: 'LH' }, // Left hip
      { idx: 24, color: '#8b5cf6', label: 'RH' }, // Right hip
      { idx: 25, color: '#eab308', label: 'LK' }, // Left knee
      { idx: 26, color: '#eab308', label: 'RK' }, // Right knee
    ];

    keyLandmarks.forEach(({ idx, color }) => {
      const p = landmarks[idx];
      if (p && p.visibility > 0.5) {
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(p.x * width, p.y * height, 6, 0, 2 * Math.PI);
        ctx.fill();
      }
    });

    // Draw hockey stick (orange line from hands to blade)
    if (this.currentStick && this.currentStick.confidence > 0.5) {
      const stick = this.currentStick;

      // Draw stick shaft (from top hand through bottom hand to blade)
      ctx.strokeStyle = '#f97316'; // Orange
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.moveTo(stick.topHand.x * width, stick.topHand.y * height);
      ctx.lineTo(stick.bottomHand.x * width, stick.bottomHand.y * height);
      ctx.lineTo(stick.blade.x * width, stick.blade.y * height);
      ctx.stroke();

      // Draw blade indicator (circle at blade position)
      ctx.fillStyle = '#f97316';
      ctx.beginPath();
      ctx.arc(stick.blade.x * width, stick.blade.y * height, 8, 0, 2 * Math.PI);
      ctx.fill();

      // Label the stick with handedness
      ctx.fillStyle = '#f97316';
      ctx.font = 'bold 12px sans-serif';
      ctx.fillText(`Stick (${stick.handedness})`, stick.topHand.x * width + 10, stick.topHand.y * height - 5);
    }

    // Draw puck (cyan circle)
    if (this.currentPuck && (performance.now() - this.currentPuck.timestamp) < 500) {
      const puck = this.currentPuck;

      // Draw puck circle
      ctx.strokeStyle = '#06b6d4'; // Cyan
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(puck.x * width, puck.y * height, 15, 0, 2 * Math.PI);
      ctx.stroke();

      // Fill with semi-transparent cyan
      ctx.fillStyle = 'rgba(6, 182, 212, 0.3)';
      ctx.fill();

      // Label with confidence
      ctx.fillStyle = '#06b6d4';
      ctx.font = 'bold 12px sans-serif';
      ctx.fillText(`Puck (${Math.round(puck.confidence * 100)}%)`, puck.x * width + 20, puck.y * height - 5);
    }

    // Draw pose status
    const poseDetected = this.poseDetector?.hasPose();
    const stickDetected = this.poseDetector?.hasStick();
    const puckDetected = this.puckDetector?.hasPuck();

    ctx.fillStyle = poseDetected ? '#22c55e' : '#ef4444';
    ctx.font = 'bold 14px sans-serif';
    ctx.fillText(poseDetected ? 'Pose Tracking Active' : 'No Pose Detected', 20, 30);

    // Status line for stick and puck
    ctx.fillStyle = stickDetected ? '#f97316' : '#666';
    ctx.fillText(stickDetected ? 'Stick: Detected' : 'Stick: -', 20, 48);

    ctx.fillStyle = puckDetected ? '#06b6d4' : '#666';
    ctx.fillText(puckDetected ? 'Puck: Detected' : 'Puck: -', 120, 48);
  },

  stopRecording() {
    // Stop detection loop
    this.stopPoseDetectionLoop();

    // Clean up pose detector
    if (this.poseDetector) {
      this.poseDetector.destroy();
      this.poseDetector = null;
    }

    // Clean up puck detector
    if (this.puckDetector) {
      this.puckDetector.destroy();
      this.puckDetector = null;
    }

    // Clear detection state
    this.currentStick = null;
    this.currentPuck = null;

    if (this.recorder && this.recorder.state !== "inactive") {
      this.recorder.stop();
    }

    if (this.stream) {
      this.stream.getTracks().forEach(track => track.stop());
      this.stream = null;
    }

    if (this.videoEl) {
      this.videoEl.srcObject = null;
    }

    this.isRecording = false;
  },

  async uploadChunk(blob) {
    // Send chunk as base64 to server
    const reader = new FileReader();
    reader.onloadend = () => {
      const base64 = reader.result.split(',')[1];
      console.log(`[VideoCapture] Sending chunk #${this.chunkCount}, size: ${blob.size} bytes`);
      this.pushEvent("video_chunk", {
        data: base64,
        chunk: this.chunkCount,
        size: blob.size,
        type: blob.type
      });
    };
    reader.onerror = (err) => {
      console.error("[VideoCapture] Failed to read chunk:", err);
    };
    reader.readAsDataURL(blob);
  },

  getBestMimeType() {
    // Preferred formats in order
    const formats = [
      'video/webm;codecs=vp9',
      'video/webm;codecs=vp8',
      'video/webm',
      'video/mp4;codecs=h264',
      'video/mp4'
    ];

    for (const format of formats) {
      if (MediaRecorder.isTypeSupported(format)) {
        return format;
      }
    }

    return null;
  },

  resizeOverlay() {
    if (!this.overlayCanvas || !this.videoEl) return;

    const rect = this.videoEl.getBoundingClientRect();

    // Only resize if we have valid dimensions
    if (rect.width > 0 && rect.height > 0) {
      this.overlayCanvas.width = rect.width;
      this.overlayCanvas.height = rect.height;
    }
  },

  destroyed() {
    this.stopRecording();
  }
};

export default VideoCapture;
