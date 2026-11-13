import Foundation
import AVFoundation
import AppKit

struct TrackMetadata: Equatable {
    let title: String
    let artist: String
    let albumArtist: String
    let album: String
    let genre: String
    let composer: String
    let year: Int
    let trackNumber: Int
    let discNumber: Int
    let artworkData: Data?

    init(
        title: String,
        artist: String,
        albumArtist: String,
        album: String,
        genre: String,
        composer: String,
        year: Int,
        trackNumber: Int,
        discNumber: Int,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.composer = composer
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.artworkData = artworkData.map(Self.normalizedArtwork)
    }

    var fileTitle: String {
        artist.isEmpty ? title : "\(artist) - \(title)"
    }

    var displayText: String {
        artist.isEmpty ? title : "\(title) — \(artist)"
    }

    var artistAndAlbumText: String {
        switch (artist.isEmpty, album.isEmpty) {
        case (false, false):
            return "\(artist) · \(album)"
        case (false, true):
            return artist
        case (true, false):
            return album
        default:
            return ""
        }
    }

    func withArtwork(_ data: Data?) -> TrackMetadata {
        TrackMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            genre: genre,
            composer: composer,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            artworkData: data ?? artworkData
        )
    }

    var avMetadataItems: [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        appendCommon(.commonKeyTitle, value: title, to: &items)
        appendCommon(.commonKeyArtist, value: artist, to: &items)
        appendCommon(.commonKeyAlbumName, value: album, to: &items)
        appendITunes(.iTunesMetadataKeyAlbumArtist, value: albumArtist, to: &items)
        appendITunes(.iTunesMetadataKeyUserGenre, value: genre, to: &items)
        appendITunes(.iTunesMetadataKeyComposer, value: composer, to: &items)

        if year > 0 {
            appendITunes(.iTunesMetadataKeyReleaseDate, value: String(year), to: &items)
        }
        if trackNumber > 0 {
            appendITunes(.iTunesMetadataKeyTrackNumber, value: String(trackNumber), to: &items)
        }
        if discNumber > 0 {
            appendITunes(.iTunesMetadataKeyDiscNumber, value: String(discNumber), to: &items)
        }
        appendArtwork(to: &items)
        return items
    }

    private func appendCommon(
        _ key: AVMetadataKey,
        value: String,
        to items: inout [AVMetadataItem]
    ) {
        guard !value.isEmpty else { return }
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = key as NSString
        item.value = value as NSString
        items.append(item)
    }

    private func appendITunes(
        _ key: AVMetadataKey,
        value: String,
        to items: inout [AVMetadataItem]
    ) {
        guard !value.isEmpty else { return }
        let item = AVMutableMetadataItem()
        item.keySpace = .iTunes
        item.key = key as NSString
        item.value = value as NSString
        items.append(item)
    }

    private func appendArtwork(to items: inout [AVMetadataItem]) {
        guard let artworkData, !artworkData.isEmpty else { return }
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeyArtwork as NSString
        item.value = artworkData as NSData
        if Self.isJPEG(artworkData) {
            item.dataType = kCMMetadataBaseDataType_JPEG as String
        } else if Self.isPNG(artworkData) {
            item.dataType = kCMMetadataBaseDataType_PNG as String
        }
        items.append(item)
    }

    private static func normalizedArtwork(_ data: Data) -> Data {
        guard !isJPEG(data), !isPNG(data) else { return data }
        guard let representation = NSBitmapImageRep(data: data),
              let png = representation.representation(using: .png, properties: [:]) else {
            return data
        }
        return png
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8])
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
