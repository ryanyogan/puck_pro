/**
 * MediaPipe Pose Detection Module
 *
 * Provides 33 body landmarks for:
 * - Shot detection via wrist velocity
 * - Form analysis (stance, rotation, follow-through)
 *
 * Runs entirely in browser at 30fps with WebGL acceleration.
 */
import { PoseLandmarker, FilesetResolver } from '@mediapipe/tasks-vision';

// MediaPipe Pose Landmark indices
export const LANDMARKS = {
  // Wrists (primary for shot detection)
  LEFT_WRIST: 15,
  RIGHT_WRIST: 16,

  // Elbows (for arm extension analysis)
  LEFT_ELBOW: 13,
  RIGHT_ELBOW: 14,

  // Shoulders (for rotation analysis)
  LEFT_SHOULDER: 11,
  RIGHT_SHOULDER: 12,

  // Hips (for stance and weight transfer)
  LEFT_HIP: 23,
  RIGHT_HIP: 24,

  // Knees (for knee bend analysis)
  LEFT_KNEE: 25,
  RIGHT_KNEE: 26,

  // Ankles (for stance width)
  LEFT_ANKLE: 27,
  RIGHT_ANKLE: 28,
};

export class PoseDetector {
  constructor(options = {}) {
    this.poseLandmarker = null;
    this.isReady = false;
    this.poseHistory = [];
    this.maxHistorySize = options.historySize || 15; // ~0.5s at 30fps

    // Shot detection state
    this.shotCooldown = false;
    this.shotCooldownMs = options.shotCooldownMs || 1000;

    // Temporal validation - require consecutive high-velocity frames
    this.shotConfidenceCounter = 0;
    this.requiredConfidenceFrames = options.requiredConfidenceFrames || 4; // ~133ms at 30fps

    // Velocity smoothing
    this.velocityHistory = [];
    this.maxVelocityHistory = 5;

    // Stick detection
    this.stickHistory = [];
    this.maxStickHistory = 10;

    // Callbacks
    this.onPoseDetected = options.onPoseDetected || null;
    this.onShotDetected = options.onShotDetected || null;
    this.onStickDetected = options.onStickDetected || null;
    this.onReady = options.onReady || null;
    this.onError = options.onError || null;
  }

  async initialize() {
    try {
      console.log('[PoseDetector] Initializing MediaPipe...');

      const vision = await FilesetResolver.forVisionTasks(
        'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/wasm'
      );

      this.poseLandmarker = await PoseLandmarker.createFromOptions(vision, {
        baseOptions: {
          modelAssetPath: 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task',
          delegate: 'GPU' // Use WebGL for performance
        },
        runningMode: 'VIDEO',
        numPoses: 1, // Single player tracking
        minPoseDetectionConfidence: 0.5,
        minPosePresenceConfidence: 0.5,
        minTrackingConfidence: 0.5
      });

      this.isReady = true;
      console.log('[PoseDetector] MediaPipe initialized successfully');

      if (this.onReady) this.onReady();
      return this;

    } catch (error) {
      console.error('[PoseDetector] Initialization error:', error);
      if (this.onError) this.onError(error);
      throw error;
    }
  }

  /**
   * Process a video frame for pose detection
   * @param {HTMLVideoElement} video - Video element with camera feed
   * @param {number} timestamp - Current timestamp in ms
   * @returns {Object|null} Pose result with landmarks
   */
  detectPose(video, timestamp) {
    if (!this.isReady || !this.poseLandmarker) return null;

    try {
      const result = this.poseLandmarker.detectForVideo(video, timestamp);

      if (result.landmarks && result.landmarks.length > 0) {
        const landmarks = result.landmarks[0];
        const poseData = {
          timestamp,
          landmarks,
          // Extract key points for shot detection
          leftWrist: landmarks[LANDMARKS.LEFT_WRIST],
          rightWrist: landmarks[LANDMARKS.RIGHT_WRIST],
          leftElbow: landmarks[LANDMARKS.LEFT_ELBOW],
          rightElbow: landmarks[LANDMARKS.RIGHT_ELBOW],
          leftShoulder: landmarks[LANDMARKS.LEFT_SHOULDER],
          rightShoulder: landmarks[LANDMARKS.RIGHT_SHOULDER],
          leftHip: landmarks[LANDMARKS.LEFT_HIP],
          rightHip: landmarks[LANDMARKS.RIGHT_HIP],
          leftKnee: landmarks[LANDMARKS.LEFT_KNEE],
          rightKnee: landmarks[LANDMARKS.RIGHT_KNEE],
        };

        // Add to history for velocity calculation
        this.poseHistory.unshift(poseData);
        if (this.poseHistory.length > this.maxHistorySize) {
          this.poseHistory.pop();
        }

        // Estimate stick position from hand positions
        const stickData = this.estimateStickPosition(poseData);
        if (stickData) {
          stickData.timestamp = timestamp;
          this.stickHistory.unshift(stickData);
          if (this.stickHistory.length > this.maxStickHistory) {
            this.stickHistory.pop();
          }

          if (this.onStickDetected) {
            this.onStickDetected(stickData);
          }
        }

        // Check for shot
        this.detectShot(poseData);

        if (this.onPoseDetected) {
          this.onPoseDetected(poseData, result);
        }

        return poseData;
      }

      return null;
    } catch (error) {
      console.error('[PoseDetector] Detection error:', error);
      return null;
    }
  }

  /**
   * Shot detection algorithm using wrist velocity with temporal validation.
   * Requires multiple consecutive high-velocity frames to prevent false positives.
   */
  detectShot(currentPose) {
    if (this.shotCooldown || this.poseHistory.length < 5) return;

    // Get wrist positions over last 5 frames (~166ms at 30fps)
    const recentPoses = this.poseHistory.slice(0, 5);

    // Calculate wrist velocity for both hands (handles left/right-handed players)
    const rightWristVelocity = this.calculateVelocity(
      recentPoses.map(p => p.rightWrist),
      recentPoses.map(p => p.timestamp)
    );

    const leftWristVelocity = this.calculateVelocity(
      recentPoses.map(p => p.leftWrist),
      recentPoses.map(p => p.timestamp)
    );

    // Use the faster wrist (handles both handedness)
    const maxVelocity = Math.max(rightWristVelocity.speed, leftWristVelocity.speed);
    const velocity = rightWristVelocity.speed > leftWristVelocity.speed
      ? rightWristVelocity
      : leftWristVelocity;

    // Apply velocity smoothing to reduce noise
    const smoothedVelocity = this.smoothVelocity(maxVelocity);

    // Calculate total displacement (not just velocity) to filter out jitter
    const start = recentPoses[recentPoses.length - 1];
    const end = recentPoses[0];
    const dominantWrist = rightWristVelocity.speed > leftWristVelocity.speed ? 'right' : 'left';
    const startWrist = dominantWrist === 'right' ? start.rightWrist : start.leftWrist;
    const endWrist = dominantWrist === 'right' ? end.rightWrist : end.leftWrist;

    // Total displacement in normalized coords (0-1 range)
    const totalDisplacement = Math.sqrt(
      Math.pow(endWrist.x - startWrist.x, 2) +
      Math.pow(endWrist.y - startWrist.y, 2)
    );

    // Shot detection thresholds (SIGNIFICANTLY increased to reduce false positives)
    const SHOT_VELOCITY_THRESHOLD = 4.0;  // Very fast wrist movement required
    const FORWARD_THRESHOLD = 0.6;        // Strong forward/upward motion required
    const MIN_DISPLACEMENT = 0.15;        // Must move at least 15% of frame width
    const STICK_VELOCITY_THRESHOLD = 2.0; // Stick blade must also be moving

    // Calculate stick velocity (require stick movement for shots)
    const stickVelocity = this.calculateStickVelocity();
    const hasStickMovement = stickVelocity > STICK_VELOCITY_THRESHOLD;

    // Check if current frame meets shot criteria
    // Now requires both wrist AND stick movement
    const meetsThreshold = smoothedVelocity > SHOT_VELOCITY_THRESHOLD &&
                           velocity.dy < -FORWARD_THRESHOLD &&
                           totalDisplacement > MIN_DISPLACEMENT &&
                           hasStickMovement;

    if (meetsThreshold) {
      // Increment confidence counter
      this.shotConfidenceCounter++;

      // Only trigger shot if we have enough consecutive high-velocity frames
      if (this.shotConfidenceCounter >= this.requiredConfidenceFrames) {
        // Reset counter and enter cooldown
        this.shotConfidenceCounter = 0;
        this.shotCooldown = true;
        setTimeout(() => { this.shotCooldown = false; }, this.shotCooldownMs);

        // Analyze shot quality
        const analysis = this.analyzeShot(recentPoses);

        console.log('[PoseDetector] Shot detected!', {
          velocity: smoothedVelocity,
          direction: velocity,
          analysis,
          confidenceFrames: this.requiredConfidenceFrames
        });

        if (this.onShotDetected) {
          this.onShotDetected({
            timestamp: currentPose.timestamp,
            velocity: smoothedVelocity,
            direction: velocity,
            analysis,
          });
        }
      }
    } else {
      // Reset confidence counter if threshold not met
      this.shotConfidenceCounter = 0;
    }
  }

  /**
   * Smooth velocity using a moving average to reduce noise/jitter
   */
  smoothVelocity(velocity) {
    this.velocityHistory.unshift(velocity);
    if (this.velocityHistory.length > this.maxVelocityHistory) {
      this.velocityHistory.pop();
    }

    // Return average of recent velocities
    const sum = this.velocityHistory.reduce((a, b) => a + b, 0);
    return sum / this.velocityHistory.length;
  }

  /**
   * Calculate velocity from position history
   */
  calculateVelocity(positions, timestamps) {
    if (positions.length < 2) return { dx: 0, dy: 0, speed: 0 };

    const start = positions[positions.length - 1];
    const end = positions[0];
    const dt = (timestamps[0] - timestamps[timestamps.length - 1]) / 1000; // seconds

    if (dt === 0 || !start || !end) return { dx: 0, dy: 0, speed: 0 };

    const dx = (end.x - start.x) / dt;
    const dy = (end.y - start.y) / dt;
    const speed = Math.sqrt(dx * dx + dy * dy);

    return { dx, dy, speed };
  }

  /**
   * Analyze shot form for quality metrics
   */
  analyzeShot(poseHistory) {
    if (poseHistory.length < 2) {
      return {
        shoulderRotation: 0,
        hipRotation: 0,
        followThrough: 0,
        weightTransfer: 0,
        kneeBend: 0,
      };
    }

    const current = poseHistory[0];
    const start = poseHistory[poseHistory.length - 1];

    // Shoulder rotation (difference between start and end)
    const shoulderRotation = this.calculateRotation(
      current.leftShoulder, current.rightShoulder,
      start.leftShoulder, start.rightShoulder
    );

    // Hip rotation
    const hipRotation = this.calculateRotation(
      current.leftHip, current.rightHip,
      start.leftHip, start.rightHip
    );

    // Follow-through: wrist above shoulder at end of shot
    // Check both wrists, use the higher one
    const rightFollowThrough = current.rightWrist.y < current.rightShoulder.y ? 1 : 0;
    const leftFollowThrough = current.leftWrist.y < current.leftShoulder.y ? 1 : 0;
    const followThrough = Math.max(rightFollowThrough, leftFollowThrough);

    // Weight transfer: hip movement during shot
    const weightTransfer = Math.abs(current.leftHip.x - start.leftHip.x) +
                          Math.abs(current.rightHip.x - start.rightHip.x);

    // Knee bend: lower Y = more bend (assuming standing)
    const avgKneeY = (current.leftKnee.y + current.rightKnee.y) / 2;
    const avgHipY = (current.leftHip.y + current.rightHip.y) / 2;
    const kneeBend = avgKneeY > avgHipY ? (avgKneeY - avgHipY) : 0;

    return {
      shoulderRotation,
      hipRotation,
      followThrough,
      weightTransfer,
      kneeBend,
    };
  }

  /**
   * Calculate rotation angle change between two poses
   */
  calculateRotation(currentLeft, currentRight, startLeft, startRight) {
    if (!currentLeft || !currentRight || !startLeft || !startRight) return 0;

    const currentAngle = Math.atan2(
      currentRight.y - currentLeft.y,
      currentRight.x - currentLeft.x
    );
    const startAngle = Math.atan2(
      startRight.y - startLeft.y,
      startRight.x - startLeft.x
    );
    return currentAngle - startAngle;
  }

  // ==================== STICK DETECTION ====================

  /**
   * Detect which hand is dominant (lower on stick).
   * Hockey grip: one hand high (guide), one hand low (power).
   */
  detectStickGrip(poseData) {
    const leftWrist = poseData.leftWrist;
    const rightWrist = poseData.rightWrist;

    if (!leftWrist || !rightWrist) return null;

    // Lower wrist (higher Y value) = bottom hand = dominant hand
    if (rightWrist.y > leftWrist.y) {
      return { topHand: 'left', bottomHand: 'right', handedness: 'right' };
    }
    return { topHand: 'right', bottomHand: 'left', handedness: 'left' };
  }

  /**
   * Estimate stick line from hand positions.
   * Returns stick position with top hand, bottom hand, and estimated blade location.
   */
  estimateStickPosition(poseData) {
    const grip = this.detectStickGrip(poseData);
    if (!grip) return null;

    const topWrist = poseData[`${grip.topHand}Wrist`];
    const bottomWrist = poseData[`${grip.bottomHand}Wrist`];

    if (!topWrist || !bottomWrist) return null;

    // Check if hands are in stick-holding position
    // Hands should be separated (one high, one low)
    const handSeparation = Math.abs(topWrist.y - bottomWrist.y);
    if (handSeparation < 0.05) return null; // Hands too close, likely not holding stick

    // Stick direction: from top hand through bottom hand, extending further
    const dx = bottomWrist.x - topWrist.x;
    const dy = bottomWrist.y - topWrist.y;
    const length = Math.sqrt(dx * dx + dy * dy);

    if (length === 0) return null;

    // Extend stick blade beyond bottom hand (normalized units)
    // ~25% of frame height represents typical stick blade distance
    const bladeExtension = 0.25;
    const bladeX = bottomWrist.x + (dx / length) * bladeExtension;
    const bladeY = bottomWrist.y + (dy / length) * bladeExtension;

    // Clamp blade position to frame bounds
    const clampedBladeX = Math.max(0, Math.min(1, bladeX));
    const clampedBladeY = Math.max(0, Math.min(1, bladeY));

    return {
      topHand: { x: topWrist.x, y: topWrist.y },
      bottomHand: { x: bottomWrist.x, y: bottomWrist.y },
      blade: { x: clampedBladeX, y: clampedBladeY },
      handedness: grip.handedness,
      confidence: Math.min(topWrist.visibility || 0, bottomWrist.visibility || 0)
    };
  }

  /**
   * Calculate stick blade velocity from history.
   * Used to validate shot detection - shots require stick movement.
   */
  calculateStickVelocity() {
    if (this.stickHistory.length < 3) return 0;

    const recent = this.stickHistory.slice(0, 3);
    const start = recent[recent.length - 1];
    const end = recent[0];

    if (!start?.blade || !end?.blade) return 0;

    const dt = (end.timestamp - start.timestamp) / 1000;
    if (dt === 0) return 0;

    const dx = end.blade.x - start.blade.x;
    const dy = end.blade.y - start.blade.y;

    return Math.sqrt(dx * dx + dy * dy) / dt;
  }

  /**
   * Get current stick position for external use
   */
  getCurrentStick() {
    return this.stickHistory.length > 0 ? this.stickHistory[0] : null;
  }

  /**
   * Check if stick is currently detected
   */
  hasStick() {
    const current = this.getCurrentStick();
    if (!current) return false;
    return (performance.now() - current.timestamp) < 500 && current.confidence > 0.5;
  }

  // ==================== END STICK DETECTION ====================

  /**
   * Get current pose for external use
   */
  getCurrentPose() {
    return this.poseHistory.length > 0 ? this.poseHistory[0] : null;
  }

  /**
   * Check if pose is currently detected
   */
  hasPose() {
    const current = this.getCurrentPose();
    if (!current) return false;
    // Check if pose is recent (within 500ms)
    return (performance.now() - current.timestamp) < 500;
  }

  /**
   * Get bounding box around detected player from pose landmarks
   * Returns {x, y, width, height} in normalized coordinates (0-1)
   */
  getPlayerBoundingBox() {
    const current = this.getCurrentPose();
    if (!current || !current.landmarks) return null;

    const landmarks = current.landmarks;
    let minX = 1, maxX = 0, minY = 1, maxY = 0;
    let visibleCount = 0;

    // Find bounds from all visible landmarks
    for (const lm of landmarks) {
      if (lm.visibility > 0.5) {
        minX = Math.min(minX, lm.x);
        maxX = Math.max(maxX, lm.x);
        minY = Math.min(minY, lm.y);
        maxY = Math.max(maxY, lm.y);
        visibleCount++;
      }
    }

    // Need at least a few visible landmarks to make a box
    if (visibleCount < 5) return null;

    // Add padding around the body
    const padding = 0.05;
    minX = Math.max(0, minX - padding);
    maxX = Math.min(1, maxX + padding);
    minY = Math.max(0, minY - padding);
    maxY = Math.min(1, maxY + padding);

    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    };
  }

  /**
   * Get current detection confidence (0-1)
   * Based on how many key landmarks are visible
   */
  getDetectionConfidence() {
    const current = this.getCurrentPose();
    if (!current || !current.landmarks) return 0;

    const keyLandmarkIndices = [
      LANDMARKS.LEFT_SHOULDER, LANDMARKS.RIGHT_SHOULDER,
      LANDMARKS.LEFT_HIP, LANDMARKS.RIGHT_HIP,
      LANDMARKS.LEFT_WRIST, LANDMARKS.RIGHT_WRIST,
    ];

    let visibleCount = 0;
    for (const idx of keyLandmarkIndices) {
      if (current.landmarks[idx]?.visibility > 0.5) {
        visibleCount++;
      }
    }

    return visibleCount / keyLandmarkIndices.length;
  }

  /**
   * Clean up resources
   */
  destroy() {
    if (this.poseLandmarker) {
      this.poseLandmarker.close();
      this.poseLandmarker = null;
    }
    this.isReady = false;
    this.poseHistory = [];
    this.velocityHistory = [];
    this.stickHistory = [];
    this.shotConfidenceCounter = 0;
    console.log('[PoseDetector] Destroyed');
  }
}

export default PoseDetector;
