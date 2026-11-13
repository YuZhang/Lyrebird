import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RecorderViewModel
    @State private var showingSettings = false
    @State private var showingFiles = false
    @State private var showingLogs = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        recordingCard
        .padding(10)
        .frame(width: 320, height: 132)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            Task { await model.refreshNowPlaying() }
        }
        .onReceive(timer) { _ in model.updateElapsed() }
        .alert("录音提示", isPresented: errorIsPresented) {
            Button("打开权限设置") { model.openRelevantPermissionSettings() }
            Button("在 Finder 中显示应用") { model.revealApplication() }
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingFiles) {
            RecordingFilesView()
                .environmentObject(model)
        }
        .sheet(isPresented: $showingLogs) {
            LogView()
                .environmentObject(model)
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    if model.automaticMode {
                        MarqueeText(
                            text: model.currentTrack?.title ?? model.detectedTrack,
                            font: .callout.weight(.semibold),
                            fontSize: 16,
                            weight: .semibold,
                            color: .primary,
                            height: 16
                        )
                        MarqueeText(
                            text: model.currentTrack?.artistAndAlbumText ?? " ",
                            font: .caption2,
                            fontSize: 11,
                            weight: .regular,
                            color: .secondary,
                            height: 12
                        )
                    } else {
                        TextField(model.isRecording ? "下一首名称" : model.currentFileName, text: $model.trackTitle)
                            .font(.callout.weight(.semibold))
                            .textFieldStyle(.plain)
                            .disabled(model.isBusy)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: statusTone.icon)
                            .foregroundStyle(statusTone.color)
                        Text(model.status)
                            .foregroundStyle(statusTone.color)
                    }
                    .font(.caption2)
                    .animation(.easeInOut(duration: 0.25), value: model.status)
                }
                Spacer()
                if model.isRecording && !model.automaticMode {
                    Button {
                        Task { await model.split() }
                    } label: {
                        Image(systemName: "scissors.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                    .accessibilityLabel("保存并切分下一首")
                }
                recordButton
                settingsMenu
            }

            Group {
                if model.automaticMode {
                    ProgressView(value: songProgress)
                        .tint(statusTone.color)
                    HStack {
                        Text("\(TrackFileNaming.shortTime(model.detectedPosition)) / \(TrackFileNaming.shortTime(model.detectedDuration))")
                        Spacer()
                        Text(model.captureFormatText)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 26)
            .opacity(model.automaticMode && model.detectedDuration > 0 ? 1 : 0)
        }
        .padding(8)
        .background(statusTone.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.25), value: statusTone)
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = model.detectedArtworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "music.note")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var songProgress: Double {
        guard model.detectedDuration > 0 else { return 0 }
        return min(max(model.detectedPosition / model.detectedDuration, 0), 1)
    }

    private enum StatusTone {
        case idle
        case waiting
        case recording
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .waiting: return .blue
            case .recording: return .red
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .idle: return "music.note"
            case .waiting: return "clock"
            case .recording: return "record.circle"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    private var statusTone: StatusTone {
        let text = model.status
        if model.errorMessage != nil || text.contains("失败") || text.contains("无法") {
            return .error
        }
        if text.contains("已保存") {
            return .success
        }
        if text.contains("跳过") || text.contains("未从头") || text.contains("不完整") {
            return .warning
        }
        if model.isRecording {
            return .recording
        }
        if model.isBusy || text.contains("等待") || text.contains("识别") {
            return .waiting
        }
        return .idle
    }

    private var settingsMenu: some View {
        Menu {
            Button("设置…") { showingSettings = true }
            Divider()
            Button("录音文件") { showingFiles = true }
            Button("查看日志") { showingLogs = true }
        } label: {
            Image(systemName: "gearshape")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var recordButton: some View {
        Button {
            Task {
                if model.isRecording {
                    await model.stop()
                } else {
                    await model.start()
                }
            }
        } label: {
            if model.isBusy && !model.isRecording {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: model.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: model.isRecording ? 28 : 36, weight: .bold))
                    .foregroundStyle(model.isBusy ? .orange : .red)
                    .frame(width: 36, height: 36)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy && !model.isRecording)
        .accessibilityLabel(model.isRecording ? "停止录音" : "开始录音")
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
