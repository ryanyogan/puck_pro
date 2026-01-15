/**
 * Simple Puck Detection Module
 *
 * Detects hockey pucks using color and shape filtering:
 * - Filters for dark/black pixels (low brightness)
 * - Finds circular blobs
 * - Filters by size and circularity
 * - Excludes player body area using pose data
 *
 * No ML model needed - just simple computer vision!
 */

export class PuckDetector {
  constructor(options = {}) {
    // Detection canvas (offscreen for processing)
    this.canvas = null;
    this.ctx = null;
    this.isReady = false;

    // Detection parameters (tunable)
    this.darkThreshold = options.darkThreshold || 60;        // Max brightness for "dark" (0-255)
    this.minPuckSize = options.minPuckSize || 10;            // Min puck diameter in pixels
    this.maxPuckSize = options.maxPuckSize || 80;            // Max puck diameter in pixels
    this.minCircularity = options.minCircularity || 0.6;     // How round (0-1, 1=perfect circle)
    this.playerBoxPadding = options.playerBoxPadding || 0.02; // Extra padding around player to exclude

    // Processing settings
    this.processWidth = options.processWidth || 320;         // Downscale for faster processing
    this.processHeight = options.processHeight || 180;

    // History for smoothing
    this.puckHistory = [];
    this.maxHistorySize = options.historySize || 5;

    // Callbacks
    this.onPuckDetected = options.onPuckDetected || null;
    this.onReady = options.onReady || null;
    this.onError = options.onError || null;
  }

  async initialize() {
    try {
      console.log('[PuckDetector] Initializing simple color-based detection...');

      // Create offscreen canvas for image processing
      this.canvas = document.createElement('canvas');
      this.canvas.width = this.processWidth;
      this.canvas.height = this.processHeight;
      this.ctx = this.canvas.getContext('2d', { willReadFrequently: true });

      this.isReady = true;
      console.log('[PuckDetector] Ready (color/shape-based detection)');

      if (this.onReady) this.onReady();
      return this;

    } catch (error) {
      console.error('[PuckDetector] Initialization error:', error);
      if (this.onError) this.onError(error);
      return this;
    }
  }

  /**
   * Detect puck in video frame
   * @param {HTMLVideoElement} video - Video element with camera feed
   * @param {number} timestamp - Current timestamp in ms
   * @param {Object} playerBox - Player bounding box to exclude {x, y, width, height} in normalized coords
   * @returns {Object|null} Puck detection result
   */
  detect(video, timestamp, playerBox = null) {
    if (!this.isReady || !this.ctx) return null;

    try {
      // Draw video frame to processing canvas (downscaled)
      this.ctx.drawImage(video, 0, 0, this.processWidth, this.processHeight);

      // Get pixel data
      const imageData = this.ctx.getImageData(0, 0, this.processWidth, this.processHeight);
      const pixels = imageData.data;

      // Find dark blobs
      const blobs = this.findDarkBlobs(pixels, this.processWidth, this.processHeight, playerBox);

      // Filter blobs by circularity and size
      const puckCandidates = blobs.filter(blob => {
        const circularity = this.calculateCircularity(blob);
        const diameter = Math.sqrt(blob.area * 4 / Math.PI);

        return circularity >= this.minCircularity &&
               diameter >= this.minPuckSize &&
               diameter <= this.maxPuckSize;
      });

      if (puckCandidates.length > 0) {
        // Take the most circular candidate
        const best = puckCandidates.reduce((a, b) =>
          this.calculateCircularity(b) > this.calculateCircularity(a) ? b : a
        );

        // Convert to normalized coordinates (0-1)
        const puckData = {
          timestamp,
          x: best.centerX / this.processWidth,
          y: best.centerY / this.processHeight,
          width: Math.sqrt(best.area * 4 / Math.PI) / this.processWidth,
          height: Math.sqrt(best.area * 4 / Math.PI) / this.processHeight,
          area: best.area,
          circularity: this.calculateCircularity(best),
          confidence: this.calculateCircularity(best), // Use circularity as confidence
        };

        // Add to history
        this.puckHistory.unshift(puckData);
        if (this.puckHistory.length > this.maxHistorySize) {
          this.puckHistory.pop();
        }

        if (this.onPuckDetected) {
          this.onPuckDetected(puckData);
        }

        return puckData;
      }

      return null;
    } catch (error) {
      console.error('[PuckDetector] Detection error:', error);
      return null;
    }
  }

  /**
   * Find dark blobs in the image using connected component labeling
   */
  findDarkBlobs(pixels, width, height, playerBox) {
    // Create binary mask of dark pixels
    const mask = new Uint8Array(width * height);

    // Convert player box to pixel coordinates
    let excludeX1 = 0, excludeY1 = 0, excludeX2 = 0, excludeY2 = 0;
    if (playerBox) {
      const pad = this.playerBoxPadding;
      excludeX1 = Math.floor((playerBox.x - pad) * width);
      excludeY1 = Math.floor((playerBox.y - pad) * height);
      excludeX2 = Math.ceil((playerBox.x + playerBox.width + pad) * width);
      excludeY2 = Math.ceil((playerBox.y + playerBox.height + pad) * height);
    }

    // Threshold for dark pixels, excluding player area
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const i = (y * width + x) * 4;

        // Skip player bounding box area
        if (playerBox && x >= excludeX1 && x <= excludeX2 && y >= excludeY1 && y <= excludeY2) {
          continue;
        }

        // Calculate brightness (simple average)
        const brightness = (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3;

        // Mark as dark if below threshold
        if (brightness < this.darkThreshold) {
          mask[y * width + x] = 1;
        }
      }
    }

    // Connected component labeling (simple flood fill approach)
    const labels = new Int32Array(width * height);
    const blobs = [];
    let currentLabel = 0;

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const idx = y * width + x;

        if (mask[idx] === 1 && labels[idx] === 0) {
          currentLabel++;
          const blob = this.floodFill(mask, labels, width, height, x, y, currentLabel);

          // Only keep blobs with reasonable size
          if (blob.area >= 20 && blob.area <= 5000) {
            blobs.push(blob);
          }
        }
      }
    }

    return blobs;
  }

  /**
   * Flood fill to find connected dark pixels
   */
  floodFill(mask, labels, width, height, startX, startY, label) {
    const stack = [[startX, startY]];
    let area = 0;
    let sumX = 0, sumY = 0;
    let minX = width, maxX = 0, minY = height, maxY = 0;

    while (stack.length > 0) {
      const [x, y] = stack.pop();
      const idx = y * width + x;

      if (x < 0 || x >= width || y < 0 || y >= height) continue;
      if (mask[idx] !== 1 || labels[idx] !== 0) continue;

      labels[idx] = label;
      area++;
      sumX += x;
      sumY += y;
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x);
      minY = Math.min(minY, y);
      maxY = Math.max(maxY, y);

      // 4-connected neighbors
      stack.push([x + 1, y]);
      stack.push([x - 1, y]);
      stack.push([x, y + 1]);
      stack.push([x, y - 1]);
    }

    return {
      label,
      area,
      centerX: sumX / area,
      centerY: sumY / area,
      minX, maxX, minY, maxY,
      boundingWidth: maxX - minX + 1,
      boundingHeight: maxY - minY + 1
    };
  }

  /**
   * Calculate circularity of a blob (1.0 = perfect circle)
   * Circularity = 4 * pi * area / perimeter^2
   * For a perfect circle, this equals 1.0
   */
  calculateCircularity(blob) {
    // Approximate perimeter from bounding box
    // For a blob, we use the aspect ratio and area to estimate circularity
    const aspectRatio = blob.boundingWidth / blob.boundingHeight;

    // Perfect circle has aspect ratio of 1
    const aspectScore = 1 - Math.abs(1 - aspectRatio);

    // Compare actual area to bounding box area (circle fills ~78.5% of its bounding box)
    const boundingArea = blob.boundingWidth * blob.boundingHeight;
    const fillRatio = blob.area / boundingArea;
    const expectedFillRatio = Math.PI / 4; // ~0.785 for a circle
    const fillScore = 1 - Math.abs(expectedFillRatio - fillRatio) / expectedFillRatio;

    // Combined circularity score
    return Math.max(0, Math.min(1, (aspectScore + fillScore) / 2));
  }

  /**
   * Get current puck position for external use
   */
  getCurrentPuck() {
    return this.puckHistory.length > 0 ? this.puckHistory[0] : null;
  }

  /**
   * Check if puck is currently detected (recent detection)
   */
  hasPuck() {
    const current = this.getCurrentPuck();
    if (!current) return false;
    return (performance.now() - current.timestamp) < 500;
  }

  /**
   * Calculate puck velocity from history
   */
  calculatePuckVelocity() {
    if (this.puckHistory.length < 3) return { dx: 0, dy: 0, speed: 0 };

    const recent = this.puckHistory.slice(0, 3);
    const start = recent[recent.length - 1];
    const end = recent[0];

    const dt = (end.timestamp - start.timestamp) / 1000;
    if (dt === 0) return { dx: 0, dy: 0, speed: 0 };

    const dx = (end.x - start.x) / dt;
    const dy = (end.y - start.y) / dt;
    const speed = Math.sqrt(dx * dx + dy * dy);

    return { dx, dy, speed };
  }

  /**
   * Clean up resources
   */
  destroy() {
    this.canvas = null;
    this.ctx = null;
    this.isReady = false;
    this.puckHistory = [];
    console.log('[PuckDetector] Destroyed');
  }
}

export default PuckDetector;
