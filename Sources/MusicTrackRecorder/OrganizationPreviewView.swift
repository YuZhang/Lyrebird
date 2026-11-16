import SwiftUI

struct OrganizationPreviewView: View {
    @EnvironmentObject private var model: RecorderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var plan: LibraryOrganizationPlan

    init(plan: LibraryOrganizationPlan) {
        _plan = State(initialValue: plan)
    }

    private var moves: [LibraryOrganizationPlan.Item] {
        plan.items.filter { $0.kind == .move }
    }

    private var conflictIndices: [Int] {
        plan.items.indices.filter { plan.items[$0].kind == .conflict }
    }

    private var unchanged: [LibraryOrganizationPlan.Item] {
        plan.items.filter { $0.kind == .unchanged }
    }

    private var skipped: [LibraryOrganizationPlan.Item] {
        plan.items.filter { $0.kind == .skipped }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Organization Preview")
                    .font(.title3.bold())
                Text(plan.directory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Move \(plan.moveCount) · Conflicts \(plan.conflictCount) · Organized \(plan.unchangedCount) · Skipped \(plan.skippedCount)")
                    .font(.callout)
            }

            List {
                if !moves.isEmpty {
                    Section("To Move \(moves.count)") {
                        ForEach(moves) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LibraryOrganizer.relativePath(item.source, root: plan.directory))
                                Text("→ \(LibraryOrganizer.relativePath(item.destination, root: plan.directory))")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .textSelection(.enabled)
                        }
                    }
                }

                if !conflictIndices.isEmpty {
                    Section("Name Conflicts \(conflictIndices.count)") {
                        ForEach(conflictIndices, id: \.self) { index in
                            let item = plan.items[index]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.source.lastPathComponent)
                                    .font(.caption.bold())
                                Text("Destination: \(LibraryOrganizer.relativePath(item.destination, root: plan.directory))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Toggle("Keep both (append a number)", isOn: $plan.items[index].keepBoth)
                                    .font(.caption)
                                Text(item.keepBoth ? "Existing files will not be overwritten" : "Skip; leave the source file in place")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !unchanged.isEmpty {
                    DisclosureGroup("Already Organized \(unchanged.count)") {
                        ForEach(unchanged) { item in
                            Text(LibraryOrganizer.relativePath(item.source, root: plan.directory))
                                .font(.caption)
                        }
                    }
                }

                if !skipped.isEmpty {
                    Section("Skipped \(skipped.count)") {
                        ForEach(skipped) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.source.lastPathComponent)
                                Text(item.reason)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .frame(minHeight: 260)

            if model.isBusy {
                Text(model.organizationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Conflicts are skipped by default; files are never overwritten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(model.isBusy)
                Button("Organize (\(plan.pendingMoveCount))") {
                    Task {
                        await model.executeOrganization(plan)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || plan.pendingMoveCount == 0)
            }
        }
        .padding(20)
        .frame(width: 700, height: 560)
    }
}
