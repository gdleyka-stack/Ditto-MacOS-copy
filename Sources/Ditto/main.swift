import AppKit
import SwiftUI

class FloatingPanel: NSWindow {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: backing,
            defer: flag
        )
        self.isMovable = false
        self.isReleasedWhenClosed = false
        self.level = .statusBar
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}

extension NSImage {
    func rounded(cornerRadius: CGFloat) -> NSImage {
        let targetSize = self.size
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        // Ensure transparent canvas
        NSColor.clear.set()
        NSRect(origin: .zero, size: targetSize).fill()
        
        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: targetSize),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.addClip()
        
        self.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: targetSize),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        return newImage
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: FloatingPanel?
    var clipboardManager = ClipboardManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy to regular so it shows up in the Dock
        NSApp.setActivationPolicy(.regular)
        
        // Load and set custom Dock icon with rounded corners (macOS style)
        let fm = FileManager.default
        let pathsAndNames: [(URL?, String, String)] = [
            (Bundle.main.url(forResource: "icon_ditto", withExtension: "png"), "icon_ditto", "png"),
            (Bundle.main.url(forResource: "icon", withExtension: "png"), "icon", "png"),
            (Bundle.main.url(forResource: "icon", withExtension: "jpg"), "icon", "jpg"),
            (URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("icon_ditto.png"), "icon_ditto", "png"),
            (URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("icon.png"), "icon", "png"),
            (URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("icon.jpg"), "icon", "jpg"),
            (URL(fileURLWithPath: "/Users/artem/Desktop/projects/Ditto/icon_ditto.png"), "icon_ditto", "png"),
            (URL(fileURLWithPath: "/Users/artem/Desktop/projects/Ditto/icon.png"), "icon", "png"),
            (URL(fileURLWithPath: "/Users/artem/Desktop/projects/Ditto/icon.jpg"), "icon", "jpg")
        ]
        
        for (url, _, _) in pathsAndNames {
            if let url = url, fm.fileExists(atPath: url.path), let iconImage = NSImage(contentsOf: url) {
                let roundedIcon = iconImage.rounded(cornerRadius: iconImage.size.width * 0.2)
                NSApp.applicationIconImage = roundedIcon
                break
            }
        }
        
        // Setup status bar item (tray icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // "doc.on.doc" is the standard macOS copy symbol
            if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Ditto") {
                image.isTemplate = true // Ensures it adjusts colors for light/dark mode
                button.image = image
            }
            button.action = #selector(toggleWindow(_:))
            button.target = self
        }
        
        setupWindow()
    }
    
    func setupWindow() {
        let contentView = ClipboardView(manager: clipboardManager)
        let hostingView = NSHostingView(rootView: contentView)
        
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        
        // Hide the panel when it loses focus (e.g. clicking outside)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
        
        self.window = panel
    }
    
    @objc func toggleWindow(_ sender: Any?) {
        guard let window = window else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            positionWindow()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func windowDidResignKey() {
        window?.orderOut(nil)
    }
    
    func positionWindow() {
        guard let window = window,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }
        
        let buttonFrame = buttonWindow.frame
        let windowFrame = window.frame
        
        // Center horizontally below the status item
        let x = buttonFrame.origin.x + (buttonFrame.width / 2) - (windowFrame.width / 2)
        // Position vertically below the status item
        let y = buttonFrame.origin.y - windowFrame.height - 4
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// Start application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
