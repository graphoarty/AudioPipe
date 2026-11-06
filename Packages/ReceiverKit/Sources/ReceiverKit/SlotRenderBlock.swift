import AVFoundation
import CAudioCore

extension SlotAudioBuffer {
    /// The 44.1 kHz stereo planar Float32 format every slot renders in.
    public static let renderFormat = AVAudioFormat(
        standardFormatWithSampleRate: SlotAudioFormat.sampleRate,
        channels: AVAudioChannelCount(SlotAudioFormat.channels)
    )!

    /// Render block for an `AVAudioSourceNode`. It captures only the C core
    /// pointer, so the audio thread does no retain/release, locking or
    /// allocation. The buffer object must outlive the node.
    public var renderBlock: AVAudioSourceNodeRenderBlock {
        let core = self.core
        return { _, _, frameCount, abl in
            ap_slot_render(core, frameCount, abl)
            return noErr
        }
    }
}
