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
        .background(LyrebirdTheme.canvas)
        .onAppear { model.setPanelVisible(true) }
        .onDisappear { model.setPanelVisible(false) }
        .onReceive(timer) { _ in model.updateElapsed() }
        .alert("Recording Notice", isPresented: errorIsPresented) {
            if let action = model.errorAction {
                Button(action == .automation ? "Open Automation Settings" : "Open Audio & Screen Recording Settings") {
                    model.openRelevantPermissionSettings()
                }
            }
            Button("OK", role: .cancel) { model.errorMessage = nil }
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    if model.automaticMode {
                        MarqueeText(
                            text: model.currentTrack?.title ?? model.detectedTrack,
                            font: .callout.weight(.semibold),
                            fontSize: 16,
                            weight: .semibold,
                            color: .primary,
                            height: 16,
                            isActive: model.isPanelVisible
                        )
                        MarqueeText(
                            text: model.currentTrack?.artistAndAlbumText ?? " ",
                            font: .caption2,
                            fontSize: 11,
                            weight: .regular,
                            color: .secondary,
                            height: 12,
                            isActive: model.isPanelVisible
                        )
                    } else {
                        TextField(model.isRecording ? "Next Track Name" : model.currentFileName, text: $model.trackTitle)
                            .font(.callout.weight(.semibold))
                            .textFieldStyle(.plain)
                            .disabled(model.isBusy)
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusTone.color)
                            .frame(width: 5, height: 5)
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
                    .accessibilityLabel("Save and Split Next Track")
                }
                recordButton
                settingsMenu
            }

            Group {
                if model.automaticMode {
                    ProgressView(value: songProgress)
                        .progressViewStyle(.linear)
                        .tint(model.isRecording ? LyrebirdTheme.accent : Color.secondary.opacity(0.35))
                    HStack {
                        Text("\(TrackFileNaming.shortTime(model.detectedPosition)) / \(TrackFileNaming.shortTime(model.detectedDuration))")
                        Spacer()
                        Text(model.captureFormatText)
                    }
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 26)
            .opacity(model.automaticMode && model.detectedDuration > 0 ? 1 : 0)
        }
        .padding(10)
        .background(LyrebirdTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(LyrebirdTheme.separator, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = model.detectedArtworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "music.note")
                .font(.callout.weight(.semibold))
                .foregroundStyle(LyrebirdTheme.accent)
                .frame(width: 46, height: 46)
                .background(LyrebirdTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
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
            case .idle, .waiting: return .secondary
            case .recording: return LyrebirdTheme.accent
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    private var statusTone: StatusTone {
        let text = model.status.lowercased()
        if model.errorMessage != nil || text.contains("failed") || text.contains("could not") || text.contains("unable") {
            return .error
        }
        if text.contains("saved") {
            return .success
        }
        if text.contains("skipped") || text.contains("not from beginning") || text.contains("incomplete") || text.contains("discarded") {
            return .warning
        }
        if model.isRecording {
            return .recording
        }
        if model.isBusy || text.contains("waiting") || text.contains("reading") || text.contains("identifying") {
            return .waiting
        }
        return .idle
    }

    private var settingsMenu: some View {
        Menu {
            Button("Settings…") { showingSettings = true }
            Divider()
            Button("Recordings") { showingFiles = true }
            Button("View Logs") { showingLogs = true }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
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
            ZStack {
                if model.isBusy && !model.isRecording {
                    ProgressView()
                        .controlSize(.small)
                } else if model.isRecording {
                    Circle()
                        .fill(LyrebirdTheme.accent)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(LyrebirdTheme.accent, lineWidth: 1.6)
                    Circle()
                        .fill(LyrebirdTheme.accent)
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy && !model.isRecording)
        .accessibilityLabel(model.isRecording ? "Stop Recording" : "Start Recording")
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
