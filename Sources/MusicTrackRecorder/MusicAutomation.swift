import Foundation

struct MusicPlayerSnapshot: Equatable {
    enum State: Equatable {
        case playing
        case paused
        case stopped
    }

    let state: State
    let trackID: String
    let track: TrackMetadata?
    let duration: Double
    let position: Double
    let sampleRate: Int

    static let stopped = MusicPlayerSnapshot(
        state: .stopped,
        trackID: "",
        track: nil,
        duration: 0,
        position: 0,
        sampleRate: 0
    )

    func withArtwork(_ artworkData: Data?) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(
            state: state,
            trackID: trackID,
            track: track?.withArtwork(artworkData),
            duration: duration,
            position: position,
            sampleRate: sampleRate
        )
    }
}

final class MusicAutomation {
    private let queue = DispatchQueue(label: "com.kimi.MusicTrackRecorder.music-automation")
    private lazy var script = NSAppleScript(source: Self.scriptSource)
    private lazy var artworkScript = NSAppleScript(source: Self.artworkScriptSource)

    func snapshot(includeArtwork: Bool = false) async throws -> MusicPlayerSnapshot {
        var snapshot = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.readSnapshot(includeArtwork: includeArtwork))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if includeArtwork, let track = snapshot.track, track.artworkData == nil {
            if let data = await ArtworkLoader.shared.artwork(for: track) {
                snapshot = MusicPlayerSnapshot(
                    state: snapshot.state,
                    trackID: snapshot.trackID,
                    track: track.withArtwork(data),
                    duration: snapshot.duration,
                    position: snapshot.position,
                    sampleRate: snapshot.sampleRate
                )
            }
        }
        return snapshot
    }

    func restartCurrentTrack() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                var errorInfo: NSDictionary?
                let script = NSAppleScript(source: """
                tell application "Music"
                    set beforePosition to player position
                    set player position to 0
                    repeat 10 times
                        if player position <= 2 then exit repeat
                        delay 0.1
                    end repeat
                    return {beforePosition, player position}
                end tell
                """)
                let result = script?.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "无法从头播放当前歌曲。"
                    if number == -1743 {
                        continuation.resume(throwing: MusicAutomationError.automationPermission)
                    } else {
                        continuation.resume(throwing: MusicAutomationError.readFailed(message))
                    }
                } else {
                    let before = result?.atIndex(1)?.doubleValue ?? -1
                    let after = result?.atIndex(2)?.doubleValue ?? -1
                    NSLog("Apple Music restart position: \(before) -> \(after)")
                    if after < 0 || after > 2 {
                        continuation.resume(throwing: MusicAutomationError.readFailed("Apple Music 未能回到歌曲开头。"))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func readSnapshot(includeArtwork: Bool) throws -> MusicPlayerSnapshot {
        guard let selectedScript = includeArtwork ? artworkScript : script else {
            throw MusicAutomationError.invalidResponse
        }
        var errorInfo: NSDictionary?
        let result = selectedScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "无法读取 Apple Music 播放状态。"
            if number == -1743 {
                throw MusicAutomationError.automationPermission
            }
            throw MusicAutomationError.readFailed(message)
        }

        guard let state = result.atIndex(1)?.stringValue?.lowercased() else {
            throw MusicAutomationError.invalidResponse
        }
        if state == "stopped" || result.numberOfItems == 1 {
            return .stopped
        }

        let title = string(at: 3, in: result)
        let artist = string(at: 4, in: result)
        let album = string(at: 6, in: result)
        let duration = max(0, result.atIndex(12)?.doubleValue ?? 0)
        let position = max(0, result.atIndex(13)?.doubleValue ?? 0)
        let persistentID = string(at: 2, in: result)
        let sampleRate = int(at: 14, in: result)
        let artworkData = includeArtwork ? result.atIndex(15)?.data : nil
        let trackID = persistentID.isEmpty
            ? "\(title)|\(artist)|\(album)|\(duration)"
            : persistentID
        let track = TrackMetadata(
            title: title.isEmpty ? "未知歌曲" : title,
            artist: artist,
            albumArtist: string(at: 5, in: result),
            album: album,
            genre: string(at: 7, in: result),
            composer: string(at: 8, in: result),
            year: int(at: 9, in: result),
            trackNumber: int(at: 10, in: result),
            discNumber: int(at: 11, in: result),
            artworkData: artworkData?.isEmpty == false ? artworkData : nil
        )

        return MusicPlayerSnapshot(
            state: state == "playing" ? .playing : .paused,
            trackID: trackID,
            track: track,
            duration: duration,
            position: position,
            sampleRate: sampleRate
        )
    }

    private func string(at index: Int, in descriptor: NSAppleEventDescriptor) -> String {
        descriptor.atIndex(index)?.stringValue ?? ""
    }

    private func int(at index: Int, in descriptor: NSAppleEventDescriptor) -> Int {
        Int(descriptor.atIndex(index)?.int32Value ?? 0)
    }

    private static let scriptSource = """
    tell application "Music"
        if it is not running then return {"stopped"}
        set stateText to "stopped"
        if player state is playing then set stateText to "playing"
        if player state is paused then set stateText to "paused"
        if stateText is "stopped" then return {"stopped"}
        set currentTrack to current track
        set sourceSampleRate to 0
        try
            set sourceSampleRate to sample rate of currentTrack
        end try
        return {stateText, persistent ID of currentTrack, name of currentTrack, artist of currentTrack, album artist of currentTrack, album of currentTrack, genre of currentTrack, composer of currentTrack, year of currentTrack, track number of currentTrack, disc number of currentTrack, duration of currentTrack, player position, sourceSampleRate}
    end tell
    """

    private static let artworkScriptSource = """
    tell application "Music"
        if it is not running then return {"stopped"}
        set stateText to "stopped"
        if player state is playing then set stateText to "playing"
        if player state is paused then set stateText to "paused"
        if stateText is "stopped" then return {"stopped"}
        set currentTrack to current track
        set sourceSampleRate to 0
        try
            set sourceSampleRate to sample rate of currentTrack
        end try
        set artworkData to ""
        try
            set artworkData to data of artwork 1 of currentTrack
        end try
        return {stateText, persistent ID of currentTrack, name of currentTrack, artist of currentTrack, album artist of currentTrack, album of currentTrack, genre of currentTrack, composer of currentTrack, year of currentTrack, track number of currentTrack, disc number of currentTrack, duration of currentTrack, player position, sourceSampleRate, artworkData}
    end tell
    """
}

enum MusicAutomationError: LocalizedError {
    case automationPermission
    case invalidResponse
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationPermission:
            return "需要“自动化”权限才能读取 Apple Music 歌曲信息。请在系统设置的“隐私与安全性 → 自动化”中允许本应用控制“音乐”，然后重新开始录音。"
        case .invalidResponse:
            return "Apple Music 返回了无法识别的播放信息。"
        case .readFailed(let message):
            return message
        }
    }
}
