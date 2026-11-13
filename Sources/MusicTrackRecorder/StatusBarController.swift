import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 24)
    private let popover = NSPopover()
    private let model: RecorderViewModel
    private var animationTimer: Timer?
    private var frame = 0

    init(model: RecorderViewModel) {
        self.model = model
        super.init()
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(model)
        )
        popover.contentSize = NSSize(width: 320, height: 132)
        popover.behavior = .transient
        popover.animates = false

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        updateImage()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateImage()
            }
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    private func updateImage() {
        frame = model.isRecording ? (frame + 1) % 4 : 0
        let image = NSImage(named: "MenuBarBird\(frame)")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.needsDisplay = true
        statusItem.button?.toolTip = model.isRecording ? "Lyrebird 录制中" : "Lyrebird 未录制"
        NSLog("Lyrebird bird frame: \(frame), recording: \(model.isRecording), loaded: \(image != nil)")
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
        menu.addItem(withTitle: "打开 Lyrebird", action: #selector(openPopover), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Lyrebird", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPopover() {
        showPopover()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
