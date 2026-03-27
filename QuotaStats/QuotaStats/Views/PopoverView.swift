import SwiftUI
import ServiceManagement

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showCursorInBar") private var showCursorInBar = true
    @AppStorage("showClaude5hInBar") private var showClaude5hInBar = false
    @AppStorage("showClaude7dInBar") private var showClaude7dInBar = true
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            cursorSection
            Divider().padding(.horizontal, 12)
            claudeSection
            Divider()
            if showSettings {
                settingsSection
                Divider()
            }
            footer
        }
        .frame(width: 300)
    }

    // MARK: - Cursor Section

    private var cursorSection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "cursorarrow.rays", title: "Cursor", isLoading: store.isLoading && store.cursorQuota == nil)

            if let error = store.cursorError {
                errorBadge(error)
            } else if let quota = store.cursorQuota {
                cursorContent(quota)
            } else {
                compactLoading
            }
        }
    }

    private func cursorContent(_ quota: CursorQuota) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                ProgressRing(progress: quota.percentage, size: 56, lineWidth: 6)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(quota.used)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("/ \(quota.limit)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("requests used")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            if let resetDate = quota.resetDate {
                resetBadge(date: resetDate, days: quota.daysUntilReset)
            }
        }
        .padding(.bottom, 14)
    }

    // MARK: - Claude Section

    private var claudeSection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "brain", title: "Claude Code", isLoading: store.isLoading && store.claudeQuota == nil)

            if let error = store.claudeError {
                errorBadge(error)
            } else if let quota = store.claudeQuota {
                claudeContent(quota)
            } else {
                compactLoading
            }
        }
    }

    private func claudeContent(_ quota: ClaudeQuota) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                ProgressRing(progress: min(quota.fiveHourPct / 100.0, 1.0), size: 56, lineWidth: 6)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(quota.fiveHourPct))%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("5h window")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let reset = quota.fiveHourReset {
                        Text("Resets \(formatTime(reset))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 16) {
                ProgressRing(progress: min(quota.sevenDayPct / 100.0, 1.0), size: 56, lineWidth: 6)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(quota.sevenDayPct))%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("7d window")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if let reset = quota.sevenDayReset {
                        resetBadge(date: reset, days: daysUntil(reset))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Shared Components

    private func sectionHeader(icon: String, title: String, isLoading: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func resetBadge(date: Date, days: Int?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            if let days, days >= 1 {
                Text("Resets \(formatDateShort(date)) · \(days)d")
            } else {
                Text("Resets \(formatTime(date))")
            }
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private func errorBadge(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var compactLoading: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show in Menu Bar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Toggle("Cursor requests", isOn: $showCursorInBar)
            Toggle("Claude 5h window", isOn: $showClaude5hInBar)
            Toggle("Claude 7d window", isOn: $showClaude7dInBar)
        }
        .font(.system(size: 12))
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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

                Button(action: { showSettings.toggle() }) {
                    Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            HStack {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at Login")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }

                Spacer()

                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Matyss/quota-stats/releases/latest")!)
                }) {
                    Text("Updates")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(.quaternary)

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private static let dateShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.timeZone = .current
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()

    private func formatDateShort(_ date: Date) -> String {
        Self.dateShortFormatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func daysUntil(_ date: Date) -> Int? {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day
        return (days ?? 0) >= 1 ? days : nil
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
