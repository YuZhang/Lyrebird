import Foundation
import AVFoundation

final class RecordingProbe {
    func run(
        outputDirectory: URL,
        adaptiveSampleRate: Bool = false,
        requestedRate: Int? = nil
    ) async -> String {
        var lines = [
            "Lyrebird Live Capture Test",
            adaptiveSampleRate ? "Duration: 6 seconds (capture, sample rate, and artwork)" : "Duration: 3 seconds (capture and ALAC encoding only)"
        ]
        let engine = AudioCaptureEngine()
        var finishedURL: URL?
        var finishedQuality: RecordingQuality?

        engine.onFileFinished = { url, quality in
            finishedURL = url
            finishedQuality = quality
        }
        engine.onSampleRateChanged = { rate in
            lines.append("Actual tap output sample rate: \(rate) Hz")
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try playMusic()
            defer { try? controlMusic("pause") }

            try await engine.start(
                outputDirectory: outputDirectory,
                title: "Live Capture Test",
                automatic: adaptiveSampleRate,
                format: .alac
            )
            lines.append("Audio stream startup: Succeeded")

            if adaptiveSampleRate {
                let snapshot = try await waitForPlayingSnapshot()
                lines.append("Source sample rate: \(snapshot.sampleRate > 0 ? "\(snapshot.sampleRate) Hz" : "Unknown; using 48000 Hz")")
                let targetRate = requestedRate ?? snapshot.sampleRate
                lines.append("Requested capture sample rate: \(targetRate) Hz")
                await engine.updateSampleRate(targetRate)
                await engine.beginTrack(title: "Live Sample Rate Test", metadata: snapshot.track)
            }

            try await Task.sleep(nanoseconds: adaptiveSampleRate ? 6_000_000_000 : 3_000_000_000)
            if adaptiveSampleRate {
                await engine.finishTrack(completed: true)
            }
            await engine.stop()
            try await Task.sleep(nanoseconds: 100_000_000)

            guard let finishedURL else {
                lines.append("File generation: Failed (no completed file received)")
                return lines.joined(separator: "\n")
            }

            let asset = AVAsset(url: finishedURL)
            guard let track = asset.tracks(withMediaType: .audio).first,
                  !track.formatDescriptions.isEmpty else {
                lines.append("File validation: Failed (no audio track)")
                return lines.joined(separator: "\n")
            }
            let description = track.formatDescriptions[0] as! CMAudioFormatDescription
            let subtype = CMFormatDescriptionGetMediaSubType(description)
            lines.append("File generation: Succeeded")
            lines.append("Codec validation: \(subtype == kAudioFormatAppleLossless ? "ALAC" : "Other (\(subtype))")")
            lines.append("File duration: \(String(format: "%.3f", asset.duration.seconds)) seconds")
            lines.append("File size: \(try Data(contentsOf: finishedURL).count) bytes")
            if let finishedQuality {
                lines.append("Write quality: \(finishedQuality.summary)")
            }
            lines.append("File path: \(finishedURL.path)")
        } catch {
            await engine.stop()
            try? controlMusic("pause")
            lines.append("Test failed: \(PermissionDiagnosticRunner.errorDetails(error))")
        }
        return lines.joined(separator: "\n")
    }

    private func waitForPlayingSnapshot() async throws -> MusicPlayerSnapshot {
        let automation = MusicAutomation()
        for _ in 0..<30 {
            let snapshot = try await automation.snapshot()
            if snapshot.state == .playing, snapshot.sampleRate > 0 {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw MusicAutomationError.readFailed("Apple Music did not start playing within the expected time.")
    }

    private func playMusic() throws {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: """
        tell application "Music"
            if (exists current track) then
                play current track
            else
                play (first track of library playlist 1)
            end if
        end tell
        """)
        _ = script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Could not play an Apple Music track."
            throw MusicAutomationError.readFailed(message)
        }
    }

    private func controlMusic(_ command: String) throws {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Music\" to \(command)")
        _ = script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Could not control Apple Music."
            throw MusicAutomationError.readFailed(message)
        }
    }
}
