import Foundation

/// The format every slot's ring buffer holds and renders: 44.1 kHz stereo,
/// planar Float32. Captured audio is converted to it before it is buffered.
public enum SlotAudioFormat {
    public static let sampleRate: Double = 44_100
    public static let channels = 2
}

public struct AudioLevels: Equatable, Sendable {
    public var peak: Float
    public var rms: Float

    public static let silent = AudioLevels(peak: 0, rms: 0)

    public init(peak: Float, rms: Float) {
        self.peak = peak
        self.rms = rms
    }

    public static func measure(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) -> AudioLevels {
        guard frames > 0 else { return .silent }
        var peak: Float = 0
        var sum: Float = 0
        for i in 0..<frames {
            let l = left[i], r = right[i]
            peak = max(peak, abs(l), abs(r))
            sum += l * l + r * r
        }
        return AudioLevels(peak: peak, rms: (sum / Float(frames * 2)).squareRoot())
    }

    /// Converts a linear amplitude to dBFS, floored at `floor`.
    public static func decibels(_ linear: Float, floor: Float = -60) -> Float {
        guard linear > 0 else { return floor }
        return max(floor, 20 * log10(linear))
    }
}
