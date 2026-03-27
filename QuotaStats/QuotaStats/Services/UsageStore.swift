import Foundation
import Combine
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var cursorQuota: QuotaInfo?
    @Published var isLoading = false
    @Published var error: String?

    @AppStorage("refreshInterval") var refreshInterval: TimeInterval = 300

    private var timer: Timer?

    func startPolling() {
        refresh()
        scheduleTimer()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let quota = try await CursorAPIClient.shared.fetchUsage()
                self.cursorQuota = quota
                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    var menuBarText: String {
        guard let q = cursorQuota else { return "—/—" }
        return "\(q.used)/\(q.limit)"
    }

    var menuBarColor: Color {
        guard let q = cursorQuota else { return .secondary }
        let pct = q.percentage
        if pct < 0.5 { return .green }
        if pct < 0.8 { return .yellow }
        return .red
    }
}
