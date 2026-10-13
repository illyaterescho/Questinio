import AVFoundation
import CoreMedia
import LocalCopilotCore

// Each capture source owns one converter, used on its serial capture queue.
final class AudioPCMConverter {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    func convert(_ input: AVAudioPCMBuffer) -> [Float] {
        guard input.frameLength > 0 else { return [] }
        if inputFormat != input.format {
            inputFormat = input.format
            converter = AVAudioConverter(from: input.format, to: output)
        }
        guard let converter else { return [] }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16000 / input.format.sampleRate) + 128)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
        var supplied = false
        var error: NSError?
        converter.convert(to: buffer, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        guard error == nil, let data = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
    func convert(_ sample: CMSampleBuffer) -> [Float] {
        guard CMSampleBufferDataIsReady(sample), let description = sample.formatDescription else { return [] }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples)) else { return [] }
        pcm.frameLength = pcm.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(sample.numSamples), into: pcm.mutableAudioBufferList) == noErr else { return [] }
        return convert(pcm)
    }
}
