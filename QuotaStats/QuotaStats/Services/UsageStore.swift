import Foundation
import Combine
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var cursorQuota: CursorQuota?
    @Published var claudeQuota: ClaudeQuota?
    @Published var isLoading = false
    @Published var cursorError: String?
    @Published var claudeError: String?

    @AppStorage("refreshInterval") var refreshInterval: TimeInterval = 300

    private var timer: Timer?

    func startPolling() {
        refresh()
        scheduleTimer()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        cursorError = nil
        claudeError = nil

        Task {
            async let cursorResult = fetchCursor()
            async let claudeResult = fetchClaude()

            let (cursor, claude) = await (cursorResult, claudeResult)

            switch cursor {
            case .success(let q): self.cursorQuota = q; self.cursorError = nil
            case .failure(let e): self.cursorError = e.localizedDescription
            }

            switch claude {
            case .success(let q): self.claudeQuota = q; self.claudeError = nil
            case .failure(let e): self.claudeError = e.localizedDescription
            }

            self.isLoading = false
        }
    }

    private func fetchCursor() async -> Result<CursorQuota, Error> {
        do { return .success(try await CursorAPIClient.shared.fetchUsage()) }
        catch { return .failure(error) }
    }

    private func fetchClaude() async -> Result<ClaudeQuota, Error> {
        do { return .success(try await ClaudeAPIClient.shared.fetchUsage()) }
        catch { return .failure(error) }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
