import SwiftUI
import ServiceManagement

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Cursor")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = store.error {
            errorView(error)
        } else if let quota = store.cursorQuota {
            quotaView(quota)
        } else {
            loadingView
        }
    }

    private func quotaView(_ quota: QuotaInfo) -> some View {
        VStack(spacing: 16) {
            ProgressRing(progress: quota.percentage, size: 88, lineWidth: 8)
                .padding(.top, 4)

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(quota.used)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("/ \(quota.limit)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text("requests used")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            if let resetDate = quota.resetDate {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Group {
                        if let days = quota.daysUntilReset {
                            Text("Resets \(formatDate(resetDate)) · \(days)d")
                        } else {
                            Text("Resets \(formatDate(resetDate))")
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
        }
        .padding(16)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading usage data…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { store.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Text("Quit QuotaStats")
                        .font(.system(size: 12))
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}
