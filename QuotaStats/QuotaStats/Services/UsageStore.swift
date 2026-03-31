import Foundation
import Combine
import SwiftUI
import os.log

@MainActor
final class UsageStore: ObservableObject {
    @Published var cursorQuota: CursorQuota?
    @Published var claudeQuota: ClaudeQuota?
    @Published var isLoading = false
    @Published var cursorError: String?
    @Published var claudeError: String?

    @AppStorage("refreshInterval") var refreshInterval: TimeInterval = 300

    private var timer: Timer?
    private var screenSleepObservers: [Any] = []
    private var isSuspended = false
    private let log = Logger(subsystem: "com.matt.quotastats", category: "Store")

    func startPolling() {
        refresh()
        scheduleTimer()
        observeScreenSleep()
    }

    func refresh() {
        guard !isLoading, !isSuspended else { return }
        isLoading = true

        Task {
            async let cursorResult = fetchCursor()
            async let claudeResult = fetchClaude()

            let (cursor, claude) = await (cursorResult, claudeResult)

            switch cursor {
            case .success(let q):
                self.cursorQuota = q
                self.cursorError = nil
            case .failure(let e):
                log.error("Cursor fetch failed: \(e.localizedDescription)")
                self.cursorError = e.localizedDescription
            }

            switch claude {
            case .success(let q):
                self.claudeQuota = q
                self.claudeError = nil
            case .failure(let e):
                log.error("Claude fetch failed: \(e.localizedDescription)")
                if self.claudeQuota != nil {
                    log.info("Keeping previous Claude data visible")
                }
                self.claudeError = self.claudeQuota == nil ? e.localizedDescription : nil
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
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func observeScreenSleep() {
        let ws = NSWorkspace.shared.notificationCenter

        let sleepObs = ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.log.info("Screen sleeping, suspending polling")
            self.isSuspended = true
            self.timer?.invalidate()
            self.timer = nil
        }

        let wakeObs = ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.log.info("Screen woke, resuming polling")
                self.isSuspended = false
                self.refresh()
                self.scheduleTimer()
            }
        }

        screenSleepObservers = [sleepObs, wakeObs]
    }
}
