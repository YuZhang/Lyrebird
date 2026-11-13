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
                    Text("权限与采集诊断")
                        .font(.title3.bold())
                    Text("实际测试系统音频流，不保存任何录音")
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
                Text("报告已保存：\(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    Task { await model.run() }
                } label: {
                    Label(model.isRunning ? "正在诊断…" : "运行诊断", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)

                Button("保存报告") { model.saveReport() }
                    .disabled(model.isRunning)

                Spacer()
                Button("关闭") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 640, height: 500)
        .onAppear {
            Task { await model.run() }
        }
    }
}
