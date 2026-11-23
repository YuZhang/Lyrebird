import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 28)
    private let popover = NSPopover()
    private let model: RecorderViewModel
    private var animationTimer: Timer?
    private var recordingObserver: AnyCancellable?
    private var frame = 0
    private lazy var images: [NSImage?] = (0..<4).map { index in
        let image = NSImage(named: "MenuBarBird\(index)")
        image?.size = NSSize(width: 26, height: 21)
        image?.isTemplate = true
        return image
    }

    init(model: RecorderViewModel) {
        self.model = model
        super.init()
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(model)
        )
        popover.contentSize = NSSize(width: 320, height: 132)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        recordingObserver = model.$isRecording.sink { [weak self] isRecording in
            Task { @MainActor in
                self?.updateRecordingState(isRecording)
            }
        }
    }

    private func updateRecordingState(_ isRecording: Bool) {
        if isRecording {
            frame = 0
            updateImage()
            guard animationTimer == nil else { return }
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advanceFrame()
                }
            }
            if let animationTimer {
                RunLoop.main.add(animationTimer, forMode: .common)
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
            frame = 0
            updateImage()
        }
    }

    private func advanceFrame() {
        frame = (frame + 1) % 4
        updateImage()
    }

    private func updateImage() {
        statusItem.button?.image = images[frame]
        statusItem.button?.needsDisplay = true
        statusItem.button?.toolTip = model.isRecording ? "Lyrebird — Recording" : "Lyrebird — Not Recording"
    }

    @objc private func handleClick() {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                showPopover()
            }
            return
        }
        showMenu()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Lyrebird", action: #selector(openPopover), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lyrebird", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPopover() {
        showPopover()
    }

    func popoverDidShow(_ notification: Notification) {
        model.setPanelVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPanelVisible(false)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
