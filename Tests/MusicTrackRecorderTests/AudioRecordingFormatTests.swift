import XCTest
import AVFoundation
@testable import MusicTrackRecorder

final class AudioRecordingFormatTests: XCTestCase {
    func testALACEncodesRealPCMWithMetadata() async throws {
        try await assertEncoding(
            format: .alac,
            expectedSubtype: kAudioFormatAppleLossless
        )
    }

    func testAACEncodesRealPCM() async throws {
        try await assertEncoding(
            format: .aac,
            expectedSubtype: kAudioFormatMPEG4AAC
        )
    }

    func testRequestedSampleRateIsUsed() {
        for format in AudioRecordingFormat.allCases {
            XCTAssertEqual(format.outputSettings(sampleRate: 44_100)[AVSampleRateKey] as? Int, 44_100)
            XCTAssertEqual(format.outputSettings(sampleRate: 96_000)[AVSampleRateKey] as? Int, 96_000)
        }
    }

    private func assertEncoding(
        format: AudioRecordingFormat,
        expectedSubtype: FourCharCode
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.wav")
        try makePCMFile(at: source)
        let output = directory.appendingPathComponent("output.m4a")

        let sourceAsset = AVAsset(url: source)
        guard let sourceTrack = sourceAsset.tracks(withMediaType: .audio).first else {
            return XCTFail("测试 WAV 没有音轨")
        }
        let reader = try AVAssetReader(asset: sourceAsset)
        let readerOutput = AVAssetReaderTrackOutput(track: sourceTrack, outputSettings: nil)
        reader.add(readerOutput)
        XCTAssertTrue(reader.startReading())

        let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: format.outputSettings)
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        writer.metadata = testMetadata.avMetadataItems
        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "无法开始写入")

        let lastEnd = CMTime(value: 48_000, timescale: 48_000)
        var sessionStarted = false
        while let sample = readerOutput.copyNextSampleBuffer() {
            if !sessionStarted {
                writer.startSession(atSourceTime: sample.presentationTimeStamp)
                sessionStarted = true
            }
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            XCTAssertTrue(input.append(sample), writer.error?.localizedDescription ?? "无法追加音频")
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: lastEnd)
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "写入失败")
        XCTAssertEqual(reader.status, .completed, reader.error?.localizedDescription ?? "读取失败")
        let outputAsset = AVAsset(url: output)
        guard let outputTrack = outputAsset.tracks(withMediaType: .audio).first,
              !outputTrack.formatDescriptions.isEmpty else {
            return XCTFail("输出文件没有可读取的音轨")
        }
        let description = outputTrack.formatDescriptions[0] as! CMAudioFormatDescription
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(description), expectedSubtype)

        let metadata = outputAsset.commonMetadata
        let title = metadata.first { $0.commonKey == .commonKeyTitle }?.value as? String
        let artwork = metadata.first { $0.commonKey == .commonKeyArtwork }?.value as? NSData
        XCTAssertEqual(title, "编码测试")
        XCTAssertNotNil(artwork)
        XCTAssertGreaterThan(try Data(contentsOf: output).count, 1_000)

        let info = try await RecordingQualityReport.info(url: output)
        XCTAssertEqual(info.codec, format.shortName)
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channels, 2)
        XCTAssertGreaterThan(info.fileSize, 1_000)
    }

    private func makePCMFile(at url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let frameCount = 48_000
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<frameCount {
                let phase = Double(frame) * 440 * 2 * Double.pi / 48_000
                samples[frame] = Float(sin(phase) * 0.25)
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private var testMetadata: TrackMetadata {
        TrackMetadata(
            title: "编码测试",
            artist: "测试艺人",
            albumArtist: "测试艺人",
            album: "测试专辑",
            genre: "测试",
            composer: "测试作曲者",
            year: 2026,
            trackNumber: 1,
            discNumber: 1,
            artworkData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        )
    }
}
