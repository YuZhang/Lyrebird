import Foundation
import AVFoundation

final class RecordingProbe {
    func run(
        outputDirectory: URL,
        adaptiveSampleRate: Bool = false,
        requestedRate: Int? = nil
    ) async -> String {
        var lines = [
            "Lyrebird 真实采集测试",
            adaptiveSampleRate ? "测试时长：6 秒（验证采集、采样率与封面状态）" : "测试时长：3 秒（仅验证采集与 ALAC 编码）"
        ]
        let engine = AudioCaptureEngine()
        var finishedURL: URL?
        var finishedQuality: RecordingQuality?

        engine.onFileFinished = { url, quality in
            finishedURL = url
            finishedQuality = quality
        }
        engine.onSampleRateChanged = { rate in
            lines.append("Tap 实际输出采样率：\(rate) Hz")
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try playMusic()
            defer { try? controlMusic("pause") }

            try await engine.start(
                outputDirectory: outputDirectory,
                title: "真机采集测试",
                automatic: adaptiveSampleRate,
                format: .alac
            )
            lines.append("音频流启动：成功")

            if adaptiveSampleRate {
                let snapshot = try await waitForPlayingSnapshot()
                lines.append("读取源采样率：\(snapshot.sampleRate > 0 ? "\(snapshot.sampleRate) Hz" : "未知，使用 48000 Hz")")
                let targetRate = requestedRate ?? snapshot.sampleRate
                lines.append("请求采集采样率：\(targetRate) Hz")
                await engine.updateSampleRate(targetRate)
                await engine.beginTrack(title: "真机采样率测试", metadata: snapshot.track)
            }

            try await Task.sleep(nanoseconds: adaptiveSampleRate ? 6_000_000_000 : 3_000_000_000)
            if adaptiveSampleRate {
                await engine.finishTrack(completed: true)
            }
            await engine.stop()
            try await Task.sleep(nanoseconds: 100_000_000)

            guard let finishedURL else {
                lines.append("文件生成：失败（未收到完成文件）")
                return lines.joined(separator: "\n")
            }

            let asset = AVAsset(url: finishedURL)
            guard let track = asset.tracks(withMediaType: .audio).first,
                  !track.formatDescriptions.isEmpty else {
                lines.append("文件验证：失败（没有音轨）")
                return lines.joined(separator: "\n")
            }
            let description = track.formatDescriptions[0] as! CMAudioFormatDescription
            let subtype = CMFormatDescriptionGetMediaSubType(description)
            lines.append("文件生成：成功")
            lines.append("编码验证：\(subtype == kAudioFormatAppleLossless ? "ALAC" : "其他（\(subtype)）")")
            lines.append("文件时长：\(String(format: "%.3f", asset.duration.seconds)) 秒")
            lines.append("文件大小：\(try Data(contentsOf: finishedURL).count) 字节")
            if let finishedQuality {
                lines.append("写入质量：\(finishedQuality.summary)")
            }
            lines.append("文件路径：\(finishedURL.path)")
        } catch {
            await engine.stop()
            try? controlMusic("pause")
            lines.append("测试失败：\(PermissionDiagnosticRunner.errorDetails(error))")
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
        throw MusicAutomationError.readFailed("Apple Music 未在预期时间内开始播放。")
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
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "无法播放 Apple Music 曲目。"
            throw MusicAutomationError.readFailed(message)
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
