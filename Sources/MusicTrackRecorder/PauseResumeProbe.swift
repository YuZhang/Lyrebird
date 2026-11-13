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
                title: "暂停恢复测试",
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

            guard let finishedURL else { return "暂停恢复测试失败：未生成文件" }
            let duration = AVAsset(url: finishedURL).duration.seconds
            let passed = fileCount == 1 && duration >= 1.2 && duration <= 2.8
            return "流程：录制 1 秒 → 暂停 1 秒 → 续录 1 秒\n文件数量：\(fileCount)\n文件时长：\(String(format: "%.3f", duration)) 秒\n暂停恢复验证：\(passed ? "通过" : "失败")\n文件路径：\(finishedURL.path)"
        } catch {
            await engine.stop()
            return "暂停恢复测试失败：\(error.localizedDescription)"
        }
    }

    private func controlMusic(_ command: String) throws {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Music\" to \(command)")
        _ = script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "无法控制 Apple Music。"
            throw MusicAutomationError.readFailed(message)
        }
    }
}
