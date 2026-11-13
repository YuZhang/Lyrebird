import SwiftUI
import AppKit

@main
struct MusicTrackRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: RecorderViewModel

    init() {
        let model = RecorderViewModel()
        _model = StateObject(wrappedValue: model)
        AppDelegate.viewModel = model
    }

    var body: some Scene {
        WindowGroup("Lyrebird") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 132)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var viewModel: RecorderViewModel?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let model = Self.viewModel {
            statusBarController = StatusBarController(model: model)
        }
        let arguments = CommandLine.arguments

        if arguments.contains("--run-elapsed-probe") {
            Task { @MainActor in
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                await Self.viewModel?.start()
                let initial = Self.viewModel?.elapsed ?? 0
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let later = Self.viewModel?.elapsed ?? 0
                await Self.viewModel?.stop()
                writeDiagnosticReport(
                    "开始计时：\(String(format: "%.2f", initial)) 秒\n2.2 秒后：\(String(format: "%.2f", later)) 秒\n计时验证：\(later >= 2 ? "通过" : "失败")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-artwork-probe") {
            Task { @MainActor in
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await Self.viewModel?.refreshNowPlaying()
                let track = Self.viewModel?.detectedTrack ?? "未读取"
                let artworkSize = Self.viewModel?.detectedArtworkData?.count ?? 0
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                writeDiagnosticReport(
                    "当前歌曲：\(track)\n封面数据：\(artworkSize) 字节\n界面封面状态：\(artworkSize > 0 ? "已加载" : "未加载")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-automatic-format-probe") {
            Task { @MainActor in
                guard let model = Self.viewModel else { return }
                let originalDirectory = model.outputDirectory
                let originalMode = model.automaticMode
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("自动格式测试", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Format Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.automaticMode = true
                model.setOutputDirectory(testDirectory)
                _ = NSAppleScript(source: "tell application \"Music\" to set player position to 0")?
                    .executeAndReturnError(nil)
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                await model.start()
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                let captureRate = model.captureSampleRate
                let sourceRate = (try? await MusicAutomation().snapshot().sampleRate) ?? 0
                let status = model.status
                let error = model.errorMessage ?? "无"
                let position = model.detectedPosition
                let fileName = model.currentFileName
                let logs = model.logEvents.prefix(5).map(\.message).joined(separator: "；")
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                model.automaticMode = originalMode
                model.setOutputDirectory(originalDirectory)
                writeDiagnosticReport(
                    "源采样率：\(sourceRate) Hz\n界面采集采样率：\(captureRate) Hz\n状态：\(status)\n文件状态：\(fileName)\n播放位置：\(position)\n日志：\(logs)\n错误：\(error)\n自动模式验证：\(sourceRate > 0 && sourceRate == captureRate ? "通过" : "失败")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-output-directory-probe") {
            Task { @MainActor in
                guard let model = Self.viewModel else { return }
                let originalDirectory = model.outputDirectory
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("目录切换测试", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Directory Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.automaticMode = false
                model.setOutputDirectory(testDirectory)
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                await model.start()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: testDirectory,
                    includingPropertiesForKeys: nil
                ).filter { $0.pathExtension == "m4a" }) ?? []
                let savedPath = UserDefaults.standard.string(forKey: "outputDirectoryPath") ?? ""
                model.setOutputDirectory(originalDirectory)
                writeDiagnosticReport(
                    "当前目录：\(testDirectory.path)\n偏好设置：\(savedPath)\n实际写入文件：\(files.count)\n目录切换验证：\(!files.isEmpty && savedPath == testDirectory.path ? "通过" : "失败")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-waiting-probe") {
            Task { @MainActor in
                guard let model = Self.viewModel else { return }
                _ = NSAppleScript(source: "tell application \"Music\" to stop")?
                    .executeAndReturnError(nil)
                let startTask = Task { @MainActor in
                    await model.start()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let waiting = model.isRecording && model.status == "等待 Apple Music 播放…"
                let waitingError = model.errorMessage ?? "无"
                _ = NSAppleScript(source: """
                tell application "Music"
                    if (exists current track) then
                        play current track
                    else
                        play (first track of library playlist 1)
                    end if
                end tell
                """)?.executeAndReturnError(nil)
                await startTask.value
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let started = model.isRecording && model.errorMessage == nil
                let startedStatus = model.status
                let startedError = model.errorMessage ?? "无"
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                writeDiagnosticReport(
                    "停止播放后点击录制：\(waiting ? "保持等待" : "失败")\n等待期间错误：\(waitingError)\n播放后启动采集：\(started ? "成功" : "失败")\n播放后状态：\(startedStatus)\n启动错误：\(startedError)",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-viewmodel-pause-probe") {
            Task { @MainActor in
                guard let model = Self.viewModel else { return }
                let originalDirectory = model.outputDirectory
                let originalMode = model.automaticMode
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("暂停恢复界面测试", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Pause Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.automaticMode = true
                model.setOutputDirectory(testDirectory)
                _ = NSAppleScript(source: """
                tell application "Music"
                    set player position to 0
                    play current track
                end tell
                """)?.executeAndReturnError(nil)
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                await model.start()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let pausedStatus = model.status
                let pausedFile = model.currentFileName
                _ = NSAppleScript(source: "tell application \"Music\" to play")?
                    .executeAndReturnError(nil)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let resumedStatus = model.status
                let resumed = model.logEvents.contains { $0.message.contains("恢复播放，继续录制") }
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                model.automaticMode = originalMode
                model.setOutputDirectory(originalDirectory)
                let passed = pausedStatus == "播放已暂停" && resumedStatus == "正在自动录音" && resumed
                writeDiagnosticReport(
                    "暂停状态：\(pausedStatus)\n暂停文件状态：\(pausedFile)\n恢复状态：\(resumedStatus)\n继续原文件：\(resumed ? "是" : "否")\n界面流程验证：\(passed ? "通过" : "失败")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-pause-resume-probe") {
            Task { @MainActor in
                let directory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    ?? FileManager.default.homeDirectoryForCurrentUser
                let report = await PauseResumeProbe().run(outputDirectory: directory)
                writeDiagnosticReport(report, arguments: arguments)
            }
            return
        }

        let adaptiveProbe = arguments.contains("--run-recording-probe-adaptive")
        if adaptiveProbe || arguments.contains("--run-recording-probe") {
            Task { @MainActor in
                let directory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    ?? FileManager.default.homeDirectoryForCurrentUser
                let requestedRate = arguments.firstIndex(of: "--probe-rate").flatMap {
                    Int(arguments[$0 + 1])
                }
                let report = await RecordingProbe().run(
                    outputDirectory: directory,
                    adaptiveSampleRate: adaptiveProbe,
                    requestedRate: requestedRate
                )
                writeDiagnosticReport(report, arguments: arguments)
            }
            return
        }

        guard arguments.contains("--run-diagnostics") else { return }
        Task { @MainActor in
            let directory = Self.viewModel?.outputDirectory
                ?? FileManager.default.homeDirectoryForCurrentUser
            let report = await PermissionDiagnosticRunner().run(outputDirectory: directory)
            writeDiagnosticReport(report, arguments: arguments)
        }
    }

    private func diagnosticOutputURL(_ arguments: [String]) -> URL? {
        guard let flag = arguments.firstIndex(of: "--diagnostic-output"), flag + 1 < arguments.count else {
            return nil
        }
        return URL(fileURLWithPath: arguments[flag + 1])
    }

    private func writeDiagnosticReport(_ report: String, arguments: [String]) {
        if let url = diagnosticOutputURL(arguments) {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try report.write(to: url, atomically: true, encoding: .utf8)
                print("诊断报告已写入：\(url.path)")
            } catch {
                print("诊断报告写入失败：\(error.localizedDescription)")
            }
        } else {
            print(report)
        }
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.viewModel, model.isRecording || model.isBusy else {
            return .terminateNow
        }

        Task { @MainActor in
            await model.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
