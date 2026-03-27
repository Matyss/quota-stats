import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellable: AnyCancellable?
    private var defaultsCancellable: AnyCancellable?

    private var showCursor: Bool { UserDefaults.standard.object(forKey: "showCursorInBar") as? Bool ?? true }
    private var showClaude5h: Bool { UserDefaults.standard.object(forKey: "showClaude5hInBar") as? Bool ?? false }
    private var showClaude7d: Bool { UserDefaults.standard.object(forKey: "showClaude7dInBar") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeStore()
        observeDefaults()
        store.startPolling()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateButtonTitle()
        }
    }

    private func updateButtonTitle() {
        guard let button = statusItem.button else { return }

        let attributed = NSMutableAttributedString()
        var hasContent = false

        if showCursor {
            let pct = store.cursorQuota?.percentage ?? 0
            appendRing(to: attributed, progress: pct, color: ringColor(for: pct))
            let text = store.cursorQuota.map { "\($0.used)/\($0.limit)" } ?? "—/—"
            appendText(to: attributed, text: " \(text)")
            hasContent = true
        }

        if showClaude5h {
            if hasContent { appendSpacer(to: attributed) }
            let pct = store.claudeQuota.map { min($0.fiveHourPct / 100.0, 1.0) } ?? 0
            appendRing(to: attributed, progress: pct, color: ringColor(for: pct))
            appendLabel(to: attributed, text: "5h")
            let text = store.claudeQuota.map { "\(Int($0.fiveHourPct))%" } ?? "—%"
            appendText(to: attributed, text: " \(text)")
            hasContent = true
        }

        if showClaude7d {
            if hasContent { appendSpacer(to: attributed) }
            let pct = store.claudeQuota.map { min($0.sevenDayPct / 100.0, 1.0) } ?? 0
            appendRing(to: attributed, progress: pct, color: ringColor(for: pct))
            appendLabel(to: attributed, text: "7d")
            let text = store.claudeQuota.map { "\(Int($0.sevenDayPct))%" } ?? "—%"
            appendText(to: attributed, text: " \(text)")
            hasContent = true
        }

        if !hasContent {
            appendText(to: attributed, text: "Q")
        }

        button.attributedTitle = attributed
    }

    private func appendText(to attributed: NSMutableAttributedString, text: String) {
        attributed.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .baselineOffset: 0.5
        ]))
    }

    private func appendLabel(to attributed: NSMutableAttributedString, text: String) {
        attributed.append(NSAttributedString(string: " \(text)", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .baselineOffset: 0.5
        ]))
    }

    private func appendSpacer(to attributed: NSMutableAttributedString) {
        attributed.append(NSAttributedString(string: "  ", attributes: [
            .font: NSFont.systemFont(ofSize: 11)
        ]))
    }

    private func appendRing(to attributed: NSMutableAttributedString, progress: Double, color: NSColor) {
        let attachment = NSTextAttachment()
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.setLineWidth(2)
            ctx.setLineCap(.round)

            ctx.setStrokeColor(color.withAlphaComponent(0.25).cgColor)
            ctx.addEllipse(in: rect.insetBy(dx: 2, dy: 2))
            ctx.strokePath()

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - 2
            let startAngle = CGFloat.pi / 2
            let endAngle = startAngle - CGFloat(progress) * 2 * .pi
            ctx.setStrokeColor(color.cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            ctx.strokePath()

            return true
        }
        image.isTemplate = false
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
        attributed.append(NSAttributedString(attachment: attachment))
    }

    private func ringColor(for progress: Double) -> NSColor {
        let c = ProgressColor.forPercentage(progress)
        return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }

    // MARK: - Observation

    private func observeStore() {
        cancellable = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.popover.isShown else { return }
                self.updateButtonTitle()
            }
    }

    private func observeDefaults() {
        defaultsCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.popover.isShown else { return }
                self.updateButtonTitle()
            }
    }

    func popoverDidClose(_ notification: Notification) {
        updateButtonTitle()
    }
}
