import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RecorderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDiagnostics = false
    @State private var previewPlan: LibraryOrganizationPlan?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(LyrebirdTheme.accent)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Recording Mode") {
                    Picker("", selection: $model.automaticMode) {
                        Text("Automatic Split").tag(true)
                        Text("Manual").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    .tint(LyrebirdTheme.accent)
                }
                .disabled(model.isRecording || model.isBusy)

                LabeledContent("Encoding") {
                    Picker("", selection: $model.recordingFormat) {
                        Text("ALAC · 24-bit").tag(AudioRecordingFormat.alac)
                        Text("AAC · 256 kbps").tag(AudioRecordingFormat.aac)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .tint(LyrebirdTheme.accent)
                }
                .disabled(model.isRecording || model.isBusy)

                Toggle("Restart from Beginning for Hi-Res Audio", isOn: $model.restartsForHigherSampleRate)
                    .tint(LyrebirdTheme.accent)
                    .disabled(model.isRecording || model.isBusy)
            }
            .padding(12)
            .background(LyrebirdTheme.card, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Save Folder") {
                    HStack(spacing: 8) {
                        Text(model.outputDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 240, alignment: .leading)
                            .textSelection(.enabled)
                        Button("Change…") { model.chooseOutputDirectory() }
                            .disabled(model.isRecording || model.isBusy)
                        Button("Open") { model.openOutputDirectory() }
                    }
                }

                LabeledContent("Music Files") {
                    HStack(spacing: 10) {
                        Button("Organize Songs…") {
                            Task { previewPlan = await model.prepareOrganizationPreview() }
                        }
                        .disabled(model.isRecording || model.isBusy)
                        if model.canUndoOrganization {
                            Button("Undo Organization") {
                                Task { await model.undoOrganization() }
                            }
                            .disabled(model.isRecording || model.isBusy)
                            .help("Restore files moved by the most recent organization")
                        }
                        if !model.organizationStatus.isEmpty {
                            Text(model.organizationStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 180, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
            .background(LyrebirdTheme.card, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Audio & Screen Recording") { model.openPermissionSettings() }
                Button("Automation") { model.openAutomationSettings() }
                Spacer()
                Button("Capture Diagnostics") { showingDiagnostics = true }
                    .tint(LyrebirdTheme.accent)
            }
        }
        .padding(16)
        .frame(width: 540, height: 330)
        .background(LyrebirdTheme.canvas)
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticView(outputDirectory: model.outputDirectory)
        }
        .sheet(item: $previewPlan) { plan in
            OrganizationPreviewView(plan: plan)
                .environmentObject(model)
        }
    }
}
