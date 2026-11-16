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
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
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
                    "Initial timer: \(String(format: "%.2f", initial)) seconds\nAfter 2.2 seconds: \(String(format: "%.2f", later)) seconds\nTimer validation: \(later >= 2 ? "Passed" : "Failed")",
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
                let track = Self.viewModel?.detectedTrack ?? "Not read"
                let artworkSize = Self.viewModel?.detectedArtworkData?.count ?? 0
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                writeDiagnosticReport(
                    "Current track: \(track)\nArtwork data: \(artworkSize) bytes\nUI artwork state: \(artworkSize > 0 ? "Loaded" : "Not loaded")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-sleep-probe") {
            Task { @MainActor in
                guard let model = Self.viewModel else { return }
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("Sleep Recovery Test", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Sleep Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.outputDirectory = testDirectory
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                await model.start()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.willSleepNotification,
                    object: nil
                )
                try? await Task.sleep(nanoseconds: 500_000_000)
                let stopped = !model.isRecording && !model.isBusy
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.didWakeNotification,
                    object: nil
                )
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: testDirectory,
                    includingPropertiesForKeys: nil
                )) ?? []
                writeDiagnosticReport(
                    "Stopped after sleep: \(stopped ? "Yes" : "No")\nRemaining audio files: \(files.count)\nSleep recovery validation: \(stopped && files.isEmpty ? "Passed" : "Failed")",
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
                defer {
                    model.automaticMode = originalMode
                    model.outputDirectory = originalDirectory
                    UserDefaults.standard.set(originalDirectory.path, forKey: "outputDirectoryPath")
                }
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("Automatic Format Test", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Format Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.automaticMode = true
                model.outputDirectory = testDirectory
                _ = NSAppleScript(source: "tell application \"Music\" to set player position to 0")?
                    .executeAndReturnError(nil)
                _ = NSAppleScript(source: "tell application \"Music\" to play current track")?
                    .executeAndReturnError(nil)
                await model.start()
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                let captureRate = model.captureSampleRate
                let sourceRate = (try? await MusicAutomation().snapshot().sampleRate) ?? 0
                let status = model.status
                let error = model.errorMessage ?? "None"
                let position = model.detectedPosition
                let fileName = model.currentFileName
                let logs = model.logEvents.prefix(5).map(\.message).joined(separator: "; ")
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                writeDiagnosticReport(
                    "Source sample rate: \(sourceRate) Hz\nUI capture sample rate: \(captureRate) Hz\nStatus: \(status)\nFile status: \(fileName)\nPlayback position: \(position)\nLogs: \(logs)\nError: \(error)\nAutomatic mode validation: \(sourceRate > 0 && sourceRate == captureRate ? "Passed" : "Failed")",
                    arguments: arguments
                )
            }
            return
        }

        if arguments.contains("--run-output-directory-probe") {
            Task { @MainActor in
                guard let model = Self.viewModel else { return }
                let originalDirectory = model.outputDirectory
                defer {
                    model.outputDirectory = originalDirectory
                }
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("Directory Switch Test", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Directory Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.automaticMode = false
                model.outputDirectory = testDirectory
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
                writeDiagnosticReport(
                    "Current folder: \(testDirectory.path)\nFiles written: \(files.count)\nDirectory switch validation: \(!files.isEmpty ? "Passed" : "Failed")",
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
                let waiting = model.isRecording && model.status == "Waiting for Apple Music…"
                let waitingError = model.errorMessage ?? "None"
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
                let startedError = model.errorMessage ?? "None"
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                writeDiagnosticReport(
                    "Record clicked while playback was stopped: \(waiting ? "Kept waiting" : "Failed")\nError while waiting: \(waitingError)\nCapture started after playback: \(started ? "Succeeded" : "Failed")\nStatus after playback: \(startedStatus)\nStartup error: \(startedError)",
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
                defer {
                    model.automaticMode = originalMode
                    model.outputDirectory = originalDirectory
                    UserDefaults.standard.set(originalDirectory.path, forKey: "outputDirectoryPath")
                }
                let testDirectory = diagnosticOutputURL(arguments)?.deletingLastPathComponent()
                    .appendingPathComponent("Pause Resume UI Test", isDirectory: true)
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Pause Test", isDirectory: true)
                try? FileManager.default.removeItem(at: testDirectory)
                try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
                model.automaticMode = true
                model.outputDirectory = testDirectory
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
                let resumed = model.logEvents.contains { $0.message.contains("Playback resumed; continuing recording") }
                await model.stop()
                _ = NSAppleScript(source: "tell application \"Music\" to pause")?
                    .executeAndReturnError(nil)
                model.automaticMode = originalMode
                model.setOutputDirectory(originalDirectory)
                let passed = pausedStatus == "Playback Paused" && resumedStatus == "Recording Automatically" && resumed
                writeDiagnosticReport(
                    "Paused status: \(pausedStatus)\nPaused file status: \(pausedFile)\nResumed status: \(resumedStatus)\nContinued original file: \(resumed ? "Yes" : "No")\nUI flow validation: \(passed ? "Passed" : "Failed")",
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
                print("Diagnostic report written: \(url.path)")
            } catch {
                print("Failed to write diagnostic report: \(error.localizedDescription)")
            }
        } else {
            print(report)
        }
        NSApp.terminate(nil)
    }

    @objc private func systemWillSleep() {
        guard let model = Self.viewModel, model.isRecording || model.isBusy else { return }
        Task { @MainActor in
            await model.stop()
        }
    }

    @objc private func systemDidWake() {
        Task { @MainActor in
            await Self.viewModel?.refreshNowPlaying()
        }
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
