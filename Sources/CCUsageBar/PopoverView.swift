import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: CCUsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let err = model.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider()

            if model.lastSevenDays.isEmpty {
                Text(model.isLoading ? "Loading…" : "No usage data yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text("Tokens").frame(width: 70, alignment: .trailing)
                        Text("Cost").frame(width: 70, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                    ForEach(model.lastSevenDays) { row in
                        HStack {
                            Text(formatDate(row.date))
                                .monospacedDigit()
                            Spacer()
                            Text(formatNumber(row.totalTokens))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            Text(String(format: "$%.2f", row.totalCost))
                                .monospacedDigit()
                                .frame(width: 70, alignment: .trailing)
                        }
                        .font(.system(size: 13))
                        .padding(.vertical, 4)
                    }
                }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text("Claude Usage").font(.headline)
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isLoading)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.currentMonthLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.2f", model.currentMonthTotal))
                    .monospacedDigit()
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            if !model.managerMessage.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("“\(model.managerMessage)”")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("— your manager")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func formatDate(_ s: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: s) else { return s }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "EEE, MMM d"
        return outFmt.string(from: d)
    }

    private func formatNumber(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 {
            return String(format: "%.1fM", d / 1_000_000)
        } else if d >= 1_000 {
            return String(format: "%.1fK", d / 1_000)
        }
        return String(n)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
