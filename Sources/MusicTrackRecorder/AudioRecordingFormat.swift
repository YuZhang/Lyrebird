import Foundation
import AVFoundation

enum AudioRecordingFormat: String, CaseIterable, Identifiable {
    case alac
    case aac

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alac: return "ALAC Lossless"
        case .aac: return "AAC 256 kbps"
        }
    }

    var shortName: String {
        switch self {
        case .alac: return "ALAC"
        case .aac: return "AAC"
        }
    }

    var detail: String {
        switch self {
        case .alac: return "Losslessly preserves captured audio; larger files"
        case .aac: return "Lossy compression; smaller files"
        }
    }

    var outputSettings: [String: Any] {
        outputSettings(sampleRate: 48_000)
    }

    func outputSettings(sampleRate: Int) -> [String: Any] {
        switch self {
        case .alac:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitDepthHintKey: 24
            ]
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000
            ]
        }
    }
}
