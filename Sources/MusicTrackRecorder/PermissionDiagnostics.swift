import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Security

final class PermissionDiagnosticRunner {
    func run(outputDirectory: URL) async -> String {
        var lines: [String] = []
        lines.append("Lyrebird权限诊断")
        lines.append("时间：\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("系统版本：\(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("应用路径：\(Bundle.main.bundleURL.path)")
        lines.append("Bundle ID：\(Bundle.main.bundleIdentifier ?? "未知")")
        lines.append("应用版本：\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "未知")")
        lines.append("签名要求：\(designatedRequirement())")
        lines.append("")

        let preflight = CGPreflightScreenCaptureAccess()
        lines.append("1. 屏幕录制预检：\(preflight ? "通过" : "未通过（仅作参考，不直接代表音频流无法启动）")")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            lines.append("2. SCShareableContent：成功（\(content.displays.count) 个显示器，\(content.applications.count) 个应用）")

            guard let display = content.displays.first else {
                lines.append("3. SCStream：未运行（没有可用显示器）")
                throw DiagnosticError.displayUnavailable
            }
            guard let music = content.applications.first(where: {
                $0.bundleIdentifier == "com.apple.Music"
            }) else {
                lines.append("3. SCStream：未运行（Apple Music 未启动）")
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
            lines.append("3. SCStream 实际启动：成功（未保存音频）")
            try? await Task.sleep(nanoseconds: 250_000_000)
            try await stream.stopCapture()
        } catch {
            if lines.count < 3 || !lines[lines.count - 1].contains("SCStream") {
                lines.append("3. SCStream 实际启动：失败")
            } else if !lines[lines.count - 1].contains("SCStream") {
                lines.append("3. SCStream 实际启动：失败")
            }
            lines.append("   错误：\(Self.errorDetails(error))")
        }

        do {
            let snapshot = try await MusicAutomation().snapshot()
            lines.append("4. Apple Music 自动化读取：成功（播放状态：\(stateText(snapshot.state))）")
        } catch {
            lines.append("4. Apple Music 自动化读取：失败")
            lines.append("   错误：\(Self.errorDetails(error))")
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let probe = outputDirectory.appendingPathComponent(".diagnostic-\(UUID().uuidString)")
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            lines.append("5. 保存目录写入：成功")
            lines.append("   目录：\(outputDirectory.path)")
        } catch {
            lines.append("5. 保存目录写入：失败")
            lines.append("   错误：\(Self.errorDetails(error))")
        }

        lines.append("")
        lines.append("说明：本报告不包含歌曲名称、封面或音频内容。")
        return lines.joined(separator: "\n")
    }

    static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code))：\(nsError.localizedDescription)"
    }

    private func designatedRequirement() -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess, let code else {
            return "无法读取"
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else {
            return "无法读取"
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text else {
            return "无法读取"
        }
        return text as String
    }

    private func stateText(_ state: MusicPlayerSnapshot.State) -> String {
        switch state {
        case .playing: return "播放中"
        case .paused: return "已暂停"
        case .stopped: return "已停止"
        }
    }
}

private enum DiagnosticError: LocalizedError {
    case displayUnavailable
    case musicUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "没有可用显示器。"
        case .musicUnavailable: return "Apple Music 未启动。"
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
    @Published var reportText = "点击“运行诊断”检查实际权限与音频采集状态。"
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
        reportText = "正在运行实际诊断…"
        reportText = await runner.run(outputDirectory: outputDirectory)
        isRunning = false
    }

    func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Lyrebird诊断.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try reportText.write(to: url, atomically: true, encoding: .utf8)
            savedReportURL = url
        } catch {
            reportText += "\n\n报告保存失败：\(PermissionDiagnosticRunner.errorDetails(error))"
        }
    }
}
