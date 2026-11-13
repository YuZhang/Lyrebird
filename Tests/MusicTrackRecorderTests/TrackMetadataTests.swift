import XCTest
import AVFoundation
@testable import MusicTrackRecorder

final class TrackMetadataTests: XCTestCase {
    private let metadata = TrackMetadata(
        title: "测试歌曲",
        artist: "测试艺人",
        albumArtist: "测试专辑艺人",
        album: "测试专辑",
        genre: "流行",
        composer: "测试作曲者",
        year: 2026,
        trackNumber: 3,
        discNumber: 1,
        artworkData: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
    )

    func testDisplayAndFileNames() {
        XCTAssertEqual(metadata.displayText, "测试歌曲 — 测试艺人")
        XCTAssertEqual(metadata.fileTitle, "测试艺人 - 测试歌曲")
        XCTAssertEqual(metadata.artistAndAlbumText, "测试艺人 · 测试专辑")
    }

    func testWithArtworkPreservesMetadata() {
        let data = Data([1, 2, 3])
        let updated = metadata.withArtwork(data)
        XCTAssertEqual(updated.title, metadata.title)
        XCTAssertEqual(updated.artist, metadata.artist)
        XCTAssertEqual(updated.album, metadata.album)
        XCTAssertEqual(updated.artworkData, data)
    }

    func testMetadataItemsContainSongInformation() {
        let items = metadata.avMetadataItems
        XCTAssertEqual(items.count, 10)
        let artwork = items.first { ($0.key as? NSString) == AVMetadataKey.commonKeyArtwork.rawValue as NSString }
        XCTAssertEqual(artwork?.value as? NSData, metadata.artworkData.map { $0 as NSData })
        XCTAssertEqual(artwork?.dataType, kCMMetadataBaseDataType_PNG as String)
        XCTAssertEqual(value(for: AVMetadataKey.commonKeyTitle.rawValue, in: items), "测试歌曲")
        XCTAssertEqual(value(for: AVMetadataKey.commonKeyArtist.rawValue, in: items), "测试艺人")
        XCTAssertEqual(value(for: AVMetadataKey.commonKeyAlbumName.rawValue, in: items), "测试专辑")
        XCTAssertEqual(value(for: AVMetadataKey.iTunesMetadataKeyComposer.rawValue, in: items), "测试作曲者")
        XCTAssertEqual(value(for: AVMetadataKey.iTunesMetadataKeyTrackNumber.rawValue, in: items), "3")
        XCTAssertEqual(value(for: AVMetadataKey.iTunesMetadataKeyReleaseDate.rawValue, in: items), "2026")
    }

    func testWriterAcceptsMetadata() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.metadata = metadata.avMetadataItems
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000
        ])
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "未知写入错误")
        writer.cancelWriting()
    }

    private func value(for key: String, in items: [AVMetadataItem]) -> String? {
        items.first { ($0.key as? NSString) == key as NSString }?.value as? String
    }
}
