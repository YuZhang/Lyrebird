import Foundation
import AVFoundation

final class PauseResumeProbe {
    func run(outputDirectory: URL) async -> String {
        let engine = AudioCaptureEngine()
        var finishedURL: URL?
        var fileCount = 0
        engine.onFileFinished = { url, _ in
            finishedURL = url
            fileCount += 1
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try controlMusic("play")
            defer { try? controlMusic("pause") }
            try await engine.start(
                outputDirectory: outputDirectory,
                title: "Pause Resume Test",
                automatic: false,
                format: .alac
            )
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.pauseTrack()
            try controlMusic("pause")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try controlMusic("play")
            await engine.resumeTrack()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await engine.stop()
            try await Task.sleep(nanoseconds: 100_000_000)

            guard let finishedURL else { return "Pause/resume test failed: no file generated" }
            let duration = AVAsset(url: finishedURL).duration.seconds
            let temporaryExists = FileManager.default.fileExists(
                atPath: TrackFileNaming.temporaryURL(for: finishedURL).path
            )
            let passed = fileCount == 1 && duration >= 1.2 && duration <= 2.8 && !temporaryExists
            return "Flow: record 1 second → pause 1 second → resume 1 second\nFile count: \(fileCount)\nFile duration: \(String(format: "%.3f", duration)) seconds\nTemporary file remains: \(temporaryExists ? "Yes" : "No")\nPause/resume validation: \(passed ? "Passed" : "Failed")\nFile path: \(finishedURL.path)"
        } catch {
            await engine.stop()
            return "Pause/resume test failed: \(error.localizedDescription)"
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
