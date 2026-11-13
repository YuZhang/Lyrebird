import SwiftUI

struct RecordingFilesView: View {
    @EnvironmentObject private var model: RecorderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.red)
                Text("Lyrebird")
                    .font(.title3.bold())
                Spacer()
                Button("Open Folder") { model.openOutputDirectory() }
                Button("Close") { dismiss() }
            }

            if model.files.isEmpty {
                Text("No recordings")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.files) { file in
                    Button {
                        if file.reportURL != nil {
                            model.revealReport(file)
                        } else {
                            model.reveal(file)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if !file.detailText.isEmpty {
                                    Text(file.detailText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 520, height: 360)
    }
}
