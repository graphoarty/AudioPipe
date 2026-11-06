import Foundation

/// Holds a slot's ring-buffer depth at its target by nudging the varispeed
/// rate. The device delivers audio on its own clock while the output device
/// runs on another, so without this the buffer slowly fills or drains.
///
/// Depth is sampled continuously and averaged over 2 s windows; at the end of
/// each window a PI controller sets the rate within ±0.1 % (under 2 cents).
public struct DriftController: Sendable {
    public var proportionalGain: Double      // rate per second of depth error
    public var integralGain: Double          // rate per (second of error × second)
    public var maxCorrection: Double
    public var windowSeconds: Double

    public private(set) var rate: Double = 1.0
    private var integral: Double = 0
    private var windowSum: Double = 0
    private var windowSamples = 0
    private var windowElapsed: Double = 0

    public init(
        proportionalGain: Double = 0.02,
        integralGain: Double = 0.0008,
        maxCorrection: Double = 0.001,
        windowSeconds: Double = 2.0
    ) {
        self.proportionalGain = proportionalGain
        self.integralGain = integralGain
        self.maxCorrection = maxCorrection
        self.windowSeconds = windowSeconds
    }

    public mutating func reset() {
        rate = 1.0
        integral = 0
        windowSum = 0
        windowSamples = 0
        windowElapsed = 0
    }

    /// Feed one depth sample. `depthSeconds` and `targetSeconds` are buffer
    /// depths in seconds; `dt` is the time since the previous sample. Returns
    /// the new rate when a window closes, otherwise nil.
    public mutating func addSample(depthSeconds: Double, targetSeconds: Double, dt: Double) -> Double? {
        windowSum += depthSeconds
        windowSamples += 1
        windowElapsed += dt
        guard windowElapsed >= windowSeconds, windowSamples > 0 else { return nil }

        let average = windowSum / Double(windowSamples)
        let elapsed = windowElapsed
        windowSum = 0
        windowSamples = 0
        windowElapsed = 0

        // Positive error: buffer too full, consume faster.
        let error = average - targetSeconds
        integral += error * elapsed
        // Anti-windup: keep the integral term alone within the correction limit.
        let integralLimit = maxCorrection / max(integralGain, .leastNonzeroMagnitude)
        integral = min(max(integral, -integralLimit), integralLimit)

        let correction = proportionalGain * error + integralGain * integral
        rate = 1.0 + min(max(correction, -maxCorrection), maxCorrection)
        return rate
    }
}
