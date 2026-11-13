import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RecorderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("设置")
                    .font(.title3.bold())
                Spacer()
                Button("完成") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("录制模式") {
                    Picker("", selection: $model.automaticMode) {
                        Text("自动分轨").tag(true)
                        Text("手动").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
                .disabled(model.isRecording || model.isBusy)

                LabeledContent("编码格式") {
                    Picker("", selection: $model.recordingFormat) {
                        Text("ALAC · 24-bit").tag(AudioRecordingFormat.alac)
                        Text("AAC · 256 kbps").tag(AudioRecordingFormat.aac)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                .disabled(model.isRecording || model.isBusy)

                Toggle("高解析就绪后从头重录", isOn: $model.restartsForHigherSampleRate)
                    .disabled(model.isRecording || model.isBusy)

                LabeledContent("保存目录") {
                    HStack(spacing: 8) {
                        Text(model.outputDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 240, alignment: .leading)
                            .textSelection(.enabled)
                        Button("更改…") { model.chooseOutputDirectory() }
                            .disabled(model.isRecording || model.isBusy)
                        Button("打开") { model.openOutputDirectory() }
                    }
                }
            }

            Divider()

            HStack {
                Button("音频／录屏权限") { model.openPermissionSettings() }
                Button("自动化权限") { model.openAutomationSettings() }
                Spacer()
                Button("采集诊断") { showingDiagnostics = true }
            }
        }
        .padding(20)
        .frame(width: 540, height: 292)
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticView(outputDirectory: model.outputDirectory)
        }
    }
}
