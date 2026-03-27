import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeStore()
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

        let text = store.menuBarText
        let attributed = NSMutableAttributedString()

        let ringAttachment = NSTextAttachment()
        let ringImage = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let progress = self.store.cursorQuota?.percentage ?? 0
            let color = self.ringColor(for: progress)

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
        ringImage.isTemplate = false
        ringAttachment.image = ringImage
        ringAttachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
        attributed.append(NSAttributedString(attachment: ringAttachment))

        attributed.append(NSAttributedString(string: " \(text)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .baselineOffset: 0.5
        ]))

        button.attributedTitle = attributed
    }

    private func ringColor(for progress: Double) -> NSColor {
        if progress < 0.5 { return .systemGreen }
        if progress < 0.8 { return .systemOrange }
        return .systemRed
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 320)
        popover.behavior = .transient
        popover.animates = true
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
                DispatchQueue.main.async {
                    self?.updateButtonTitle()
                }
            }
    }
}
