import Foundation
import AVFoundation

struct RecordingQuality: Equatable {
    var droppedFrames: Int64 = 0
    var droppedBuffers = 0
    var maximumBufferedBuffers = 0
    var writtenFrames: Int64 = 0
    var metadataWarnings: [String] = []

    var hasIssues: Bool {
        droppedFrames > 0 || droppedBuffers > 0
    }

    var summary: String {
        guard hasIssues else { return "No dropped frames caused by write congestion" }
        let bufferUnit = droppedBuffers == 1 ? "buffer" : "buffers"
        let frameUnit = droppedFrames == 1 ? "frame" : "frames"
        return "Dropped \(droppedBuffers) audio \(bufferUnit) and \(droppedFrames) \(frameUnit)"
    }
}

struct RecordingFileInfo: Equatable {
    let duration: Double
    let fileSize: Int64
    let sampleRate: Int
    let channels: Int
    let codec: String
}

enum RecordingQualityReport {
    static func info(url: URL) async throws -> RecordingFileInfo {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        var codec = "Unknown"
        var sampleRate = 0.0
        var channels = 0
        if let track = tracks.first {
            let descriptions = try await track.load(.formatDescriptions)
            if let first = descriptions.first {
                let description = first as! CMAudioFormatDescription
                let subtype = CMFormatDescriptionGetMediaSubType(description)
                codec = codecName(subtype)
                if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                    sampleRate = basic.pointee.mSampleRate
                    channels = Int(basic.pointee.mChannelsPerFrame)
                }
            }
        }
        return RecordingFileInfo(
            duration: duration,
            fileSize: fileSize,
            sampleRate: Int(sampleRate),
            channels: channels,
            codec: codec
        )
    }

    private static func codecName(_ subtype: FourCharCode) -> String {
        switch subtype {
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatMPEG4AAC: return "AAC"
        default: return "FourCC \(subtype)"
        }
    }
}
