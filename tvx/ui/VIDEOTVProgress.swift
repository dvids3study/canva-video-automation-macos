import AppKit
import Foundation

final class ProgressController: NSObject {
    private let statusURL: URL
    private var window: NSWindow!
    private var stageLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var percentLabel: NSTextField!
    private var etaLabel: NSTextField!
    private var iconView: NSImageView!
    private var timer: Timer?
    private var successCloseScheduled = false

    init(statusURL: URL) {
        self.statusURL = statusURL
        super.init()
        buildUI()
        startPolling()
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = .labelColor
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    private func buildUI() {
        let width: CGFloat = 390
        let height: CGFloat = 170

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 18
        visual.layer?.masksToBounds = true
        window.contentView = visual

        iconView = NSImageView(frame: NSRect(x: 20, y: 126, width: 24, height: 24))
        iconView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
        visual.addSubview(iconView)

        let title = makeLabel("VIDEOTV", size: 17, weight: .semibold)
        title.frame = NSRect(x: 52, y: 127, width: 270, height: 24)
        visual.addSubview(title)

        let closeButton = NSButton(frame: NSRect(x: 348, y: 126, width: 24, height: 24))
        closeButton.title = "×"
        closeButton.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeVisualOnly)
        closeButton.toolTip = "Ocultar ventana"
        visual.addSubview(closeButton)

        stageLabel = makeLabel("Preparando...", size: 14, weight: .medium)
        stageLabel.frame = NSRect(x: 20, y: 91, width: 350, height: 20)
        visual.addSubview(stageLabel)

        detailLabel = makeLabel("", size: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.frame = NSRect(x: 20, y: 70, width: 350, height: 18)
        visual.addSubview(detailLabel)

        progressBar = NSProgressIndicator(frame: NSRect(x: 20, y: 43, width: 300, height: 12))
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        visual.addSubview(progressBar)

        percentLabel = makeLabel("0%", size: 12, weight: .medium)
        percentLabel.alignment = .right
        percentLabel.frame = NSRect(x: 325, y: 39, width: 45, height: 18)
        visual.addSubview(percentLabel)

        etaLabel = makeLabel("", size: 11, weight: .regular)
        etaLabel.textColor = .tertiaryLabelColor
        etaLabel.frame = NSRect(x: 20, y: 15, width: 350, height: 18)
        visual.addSubview(etaLabel)

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - width - 22, y: f.maxY - height - 22))
        } else {
            window.center()
        }
        window.orderFrontRegardless()
    }

    @objc private func closeVisualOnly() {
        // Solo oculta la interfaz. El proceso externo de FFmpeg sigue corriendo.
        timer?.invalidate()
        window.close()
        NSApp.terminate(nil)
    }

    private func etaText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        if seconds < 60 { return "Tiempo aprox.: \(seconds) s" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "Tiempo aprox.: \(m) min" : "Tiempo aprox.: \(m) min \(s) s"
    }

    private func startPolling() {
        readStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.readStatus()
        }
    }

    private func readStatus() {
        guard let raw = try? String(contentsOf: statusURL, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .newlines)
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return }
        let state = parts[0], stage = parts[1], detail = parts[2]
        let progress = Double(parts[3]) ?? 0
        let eta = Int(parts[4]) ?? 0

        DispatchQueue.main.async {
            self.stageLabel.stringValue = stage
            self.detailLabel.stringValue = detail
            self.progressBar.doubleValue = max(0, min(100, progress))
            self.percentLabel.stringValue = state == "error" ? "" : "\(Int(progress.rounded()))%"
            self.etaLabel.stringValue = state == "processing" ? self.etaText(eta) : ""

            switch state {
            case "success":
                self.iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
                if !self.successCloseScheduled {
                    self.successCloseScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { NSApp.terminate(nil) }
                }
            case "error":
                self.iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                self.progressBar.doubleValue = 100
                // En error la ventana queda abierta hasta pulsar X.
            default:
                self.iconView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard CommandLine.arguments.count >= 2 else { exit(2) }
let controller = ProgressController(statusURL: URL(fileURLWithPath: CommandLine.arguments[1]))
withExtendedLifetime(controller) { app.run() }
