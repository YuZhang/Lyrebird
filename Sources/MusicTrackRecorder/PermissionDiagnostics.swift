import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Security

final class PermissionDiagnosticRunner {
    func run(outputDirectory: URL) async -> String {
        var lines: [String] = []
        lines.append("Lyrebird Permission Diagnostics")
        lines.append("Time: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("System version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Application path: \(Bundle.main.bundleURL.path)")
        lines.append("Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        lines.append("Application version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown")")
        lines.append("Designated requirement: \(designatedRequirement())")
        lines.append("")

        let preflight = CGPreflightScreenCaptureAccess()
        lines.append("1. Screen recording preflight: \(preflight ? "Passed" : "Not passed (informational only; does not prove the audio stream cannot start)")")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            lines.append("2. SCShareableContent: Succeeded (\(content.displays.count) displays, \(content.applications.count) applications)")

            guard let display = content.displays.first else {
                lines.append("3. SCStream: Not run (no display available)")
                throw DiagnosticError.displayUnavailable
            }
            guard let music = content.applications.first(where: {
                $0.bundleIdentifier == "com.apple.Music"
            }) else {
                lines.append("3. SCStream: Not run (Apple Music is not running)")
                throw DiagnosticError.musicUnavailable
            }

            let filter = SCContentFilter(display: display, including: [music], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            let sink = DiagnosticAudioSink()
            let queue = DispatchQueue(label: "com.kimi.MusicTrackRecorder.diagnostics")
            try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
            lines.append("3. SCStream startup: Succeeded (audio not saved)")
            try? await Task.sleep(nanoseconds: 250_000_000)
            try await stream.stopCapture()
        } catch {
            if lines.count < 3 || !lines[lines.count - 1].contains("SCStream") {
                lines.append("3. SCStream startup: Failed")
            } else if !lines[lines.count - 1].contains("SCStream") {
                lines.append("3. SCStream startup: Failed")
            }
            lines.append("   Error: \(Self.errorDetails(error))")
        }

        do {
            let snapshot = try await MusicAutomation().snapshot()
            lines.append("4. Apple Music automation read: Succeeded (playback state: \(stateText(snapshot.state)))")
        } catch {
            lines.append("4. Apple Music automation read: Failed")
            lines.append("   Error: \(Self.errorDetails(error))")
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let probe = outputDirectory.appendingPathComponent(".diagnostic-\(UUID().uuidString)")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            lines.append("5. Save folder write: Succeeded")
            lines.append("   Folder: \(outputDirectory.path)")
        } catch {
            lines.append("5. Save folder write: Failed")
            lines.append("   Error: \(Self.errorDetails(error))")
        }

        lines.append("")
        lines.append("Note: This report contains no track names, artwork, or audio content.")
        return lines.joined(separator: "\n")
    }

    static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }

    private func designatedRequirement() -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else {
            return "Unavailable"
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else {
            return "Unavailable"
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text else {
            return "Unavailable"
        }
        return text as String
    }

    private func stateText(_ state: MusicPlayerSnapshot.State) -> String {
        switch state {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }
}

private enum DiagnosticError: LocalizedError {
    case displayUnavailable
    case musicUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "No display is available."
        case .musicUnavailable: return "Apple Music is not running."
        }
    }
}

private final class DiagnosticAudioSink: NSObject, SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {}
}

@MainActor
final class PermissionDiagnosticsViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var reportText = "Click Run Diagnostics to check permissions and audio capture."
    @Published private(set) var savedReportURL: URL?

    let outputDirectory: URL
    private let runner = PermissionDiagnosticRunner()

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        savedReportURL = nil
        reportText = "Running diagnostics…"
        reportText = await runner.run(outputDirectory: outputDirectory)
        isRunning = false
    }

    func scanPunctuationConflicts() async {
        guard !isRunning else { return }
        isRunning = true
        savedReportURL = nil
        reportText = "Scanning the library for punctuation variants…"
        reportText = await LibraryPunctuationScanner().scan(in: outputDirectory)
        isRunning = false
    }

    func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Lyrebird Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try reportText.write(to: url, atomically: true, encoding: .utf8)
            savedReportURL = url
        } catch {
            reportText += "\n\nFailed to save report: \(PermissionDiagnosticRunner.errorDetails(error))"
        }
    }
}
