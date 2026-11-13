import SwiftUI

struct LogView: View {
    @EnvironmentObject private var model: RecorderViewModel
    @Environment(\.dismiss) private var dismiss

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.red)
                Text("Lyrebird Logs")
                    .font(.title3.bold())
                Spacer()
                Button("Clear") { model.clearLogs() }
                    .disabled(model.logEvents.isEmpty)
                Button("Close") { dismiss() }
            }

            if model.logEvents.isEmpty {
                Text("No log entries")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.logEvents) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Text(formatter.string(from: event.date))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)
                        Image(systemName: icon(for: event.level))
                                .foregroundStyle(color(for: event.level))
                                .frame(width: 16)
                        Text(event.message)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 600, height: 400)
    }

    private func icon(for level: LogLevel) -> String {
        switch level {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
