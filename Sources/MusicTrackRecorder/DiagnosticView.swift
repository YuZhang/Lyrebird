import SwiftUI

struct DiagnosticView: View {
    @StateObject private var model: PermissionDiagnosticsViewModel
    @Environment(\.dismiss) private var dismiss

    init(outputDirectory: URL) {
        _model = StateObject(
            wrappedValue: PermissionDiagnosticsViewModel(outputDirectory: outputDirectory)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Permission & Capture Diagnostics")
                        .font(.title3.bold())
                    Text("Tests the system audio stream without saving a recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(model.reportText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))

            if let url = model.savedReportURL {
                Text("Report saved: \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await model.run() }
                } label: {
                    Label(model.isRunning ? "Diagnosing…" : "Run Diagnostics", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)

                Button("Scan Punctuation Conflicts") {
                    Task { await model.scanPunctuationConflicts() }
                }
                .disabled(model.isRunning)

                Button("Save Report") { model.saveReport() }
                    .disabled(model.isRunning)

                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 640, height: 500)
        .onAppear {
            Task { await model.run() }
        }
    }
}
