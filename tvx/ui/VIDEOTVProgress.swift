import AppKit
import Darwin
import Foundation

// MARK: - Glass morphism helpers

private func glassWhite(_ alpha: CGFloat) -> NSColor {
    NSColor(calibratedWhite: 1.0, alpha: alpha)
}

private func glassBlack(_ alpha: CGFloat) -> NSColor {
    NSColor(calibratedWhite: 0.0, alpha: alpha)
}

/// Fondo de vidrio: material del sistema + gradiente, borde luminoso y
/// reflejo interior. La ventana es transparente para que el vidrio se vea.
final class GlassBackgroundView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 26
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = 26
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()

        // Tinte oscuro para que el vidrio se lea sobre fondos claros.
        let colors = [
            NSColor(calibratedWhite: 0.13, alpha: 0.86).cgColor,
            NSColor(calibratedWhite: 0.03, alpha: 0.70).cgColor
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end: CGPoint(x: 0, y: bounds.minY),
                                   options: [])
        }

        // Reflejo superior, como el borde iluminado de la referencia.
        let highlights = [
            glassWhite(0.20).cgColor,
            glassWhite(0.04).cgColor,
            glassWhite(0.0).cgColor
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: highlights as CFArray,
                                     locations: [0.0, 0.35, 1.0]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end: CGPoint(x: 0, y: bounds.midY),
                                   options: [])
        }
        ctx.restoreGState()

        // Borde exterior de 1 px.
        ctx.addPath(path)
        ctx.setStrokeColor(glassWhite(0.24).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // Línea interior superior más brillante.
        let inner = rect.insetBy(dx: 1, dy: 1)
        let innerPath = CGPath(roundedRect: inner, cornerWidth: radius - 1, cornerHeight: radius - 1, transform: nil)
        ctx.addPath(innerPath)
        ctx.setStrokeColor(glassWhite(0.10).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

/// Cápsula de vidrio para el chip VIDEOTV.
final class GlassChipView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        glassWhite(0.085).setFill()
        path.fill()
        glassWhite(0.20).setStroke()
        path.lineWidth = 1
        path.stroke()

        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: bounds.height / 2, y: bounds.maxY - 1))
        highlight.line(to: NSPoint(x: bounds.maxX - bounds.height / 2, y: bounds.maxY - 1))
        glassWhite(0.22).setStroke()
        highlight.lineWidth = 1
        highlight.stroke()
    }
}

/// Botón tipo píldora de vidrio. El color base cambia para Detener.
final class GlassButton: NSButton {
    var baseColor: NSColor = glassWhite(0.10)
    var rimColor: NSColor = glassWhite(0.22)
    private var hovering = false
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        let alpha = hovering ? min(1.0, baseColor.alphaComponent + 0.08) : baseColor.alphaComponent
        baseColor.withAlphaComponent(alpha).setFill()
        path.fill()
        rimColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: bounds.height / 2, y: bounds.maxY - 2))
        highlight.line(to: NSPoint(x: bounds.maxX - bounds.height / 2, y: bounds.maxY - 2))
        glassWhite(0.16).setStroke()
        highlight.lineWidth = 1
        highlight.stroke()

        super.draw(dirtyRect)
    }
}

/// Pista de progreso de vidrio con relleno luminoso.
final class GlassProgressView: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var isIndeterminate = false {
        didSet {
            if isIndeterminate { startShimmer() } else { stopShimmer() }
        }
    }

    private var phase: CGFloat = 0
    private var shimmerTimer: Timer?

    private func startShimmer() {
        stopShimmer()
        phase = 0
        shimmerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.018
            if self.phase > 1 { self.phase = 0 }
            self.needsDisplay = true
        }
    }

    private func stopShimmer() {
        shimmerTimer?.invalidate()
        shimmerTimer = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds,
                                 xRadius: bounds.height / 2,
                                 yRadius: bounds.height / 2)
        glassWhite(0.09).setFill()
        track.fill()
        glassWhite(0.18).setStroke()
        track.lineWidth = 1
        track.stroke()

        let inner = bounds.insetBy(dx: 2, dy: 2)
        guard inner.width > 0, inner.height > 0 else { return }

        if isIndeterminate {
            let segmentWidth = inner.width * 0.30
            let travel = inner.width + segmentWidth
            let x = max(inner.minX - segmentWidth, inner.minX + phase * travel - segmentWidth)
            let segment = NSBezierPath(roundedRect: NSRect(x: x, y: inner.minY, width: segmentWidth, height: inner.height),
                                       xRadius: inner.height / 2,
                                       yRadius: inner.height / 2)
            drawFill(on: segment, from: x, to: x + segmentWidth, in: inner)
            return
        }

        let width = max(0, min(1, progress)) * inner.width
        guard width > 0 else { return }
        let fill = NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height),
                                xRadius: inner.height / 2,
                                yRadius: inner.height / 2)
        drawFill(on: fill, from: inner.minX, to: inner.minX + width, in: inner)
    }

    private func drawFill(on path: NSBezierPath, from x0: CGFloat, to x1: CGFloat, in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = glassWhite(0.28)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = .zero
        shadow.set()
        path.addClip()
        let colors = [
            NSColor(calibratedWhite: 0.98, alpha: 0.98),
            NSColor(calibratedWhite: 0.72, alpha: 0.92),
            NSColor(calibratedWhite: 0.56, alpha: 0.88)
        ]
        if let gradient = NSGradient(colors: colors) {
            gradient.draw(in: NSRect(x: x0, y: rect.minY, width: max(1, x1 - x0), height: rect.height),
                          angle: 0)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Controller

final class ProgressController: NSObject {
    private let statusURL: URL
    private let pidURL: URL
    private var window: NSWindow!
    private var stageLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progressView: GlassProgressView!
    private var percentLabel: NSTextField!
    private var etaLabel: NSTextField!
    private var iconView: NSImageView!
    private var stopButton: GlassButton!
    private var timer: Timer?
    private var successCloseScheduled = false
    private var interrupted = false
    private var stopping = false
    private var startedAt: Date?

    init(statusURL: URL) {
        self.statusURL = statusURL
        self.pidURL = statusURL.deletingLastPathComponent().appendingPathComponent("processor.pid")
        super.init()
        buildUI()
        startPolling()
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func styledButton(title: String,
                              frame: NSRect,
                              font: NSFont,
                              base: NSColor,
                              rim: NSColor,
                              symbol: String? = nil) -> GlassButton {
        let button = GlassButton(frame: frame)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.alignment = .center
        button.font = font
        button.baseColor = base
        button.rimColor = rim
        button.contentTintColor = .white
        let color = NSColor.white
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
        }
        return button
    }

    private func buildUI() {
        let width: CGFloat = 420
        let height: CGFloat = 224

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)

        let glass = GlassBackgroundView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        glass.autoresizingMask = [.width, .height]
        window.contentView = glass

        let chip = GlassChipView(frame: NSRect(x: 22, y: 178, width: 150, height: 34))
        glass.addSubview(chip)

        iconView = NSImageView(frame: NSRect(x: 12, y: 8, width: 18, height: 18))
        iconView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        iconView.contentTintColor = .white
        chip.addSubview(iconView)

        let title = makeLabel("VIDEOTV", size: 15, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: 38, y: 7, width: 100, height: 20)
        chip.addSubview(title)

        let close = styledButton(title: "×",
                                 frame: NSRect(x: 370, y: 181, width: 28, height: 28),
                                 font: NSFont.systemFont(ofSize: 18, weight: .regular),
                                 base: glassWhite(0.03),
                                 rim: glassWhite(0.10))
        close.target = self
        close.action = #selector(closeVisualOnly)
        close.toolTip = "Ocultar ventana (el proceso sigue)"
        glass.addSubview(close)

        stageLabel = makeLabel("Preparando...", size: 15, weight: .semibold)
        stageLabel.textColor = .white
        stageLabel.frame = NSRect(x: 24, y: 149, width: 300, height: 22)
        glass.addSubview(stageLabel)

        percentLabel = makeLabel("0%", size: 12, weight: .medium)
        percentLabel.textColor = glassWhite(0.72)
        percentLabel.alignment = .right
        percentLabel.frame = NSRect(x: 336, y: 151, width: 60, height: 18)
        glass.addSubview(percentLabel)

        detailLabel = makeLabel("", size: 12, weight: .regular)
        detailLabel.textColor = glassWhite(0.58)
        detailLabel.frame = NSRect(x: 24, y: 125, width: 372, height: 18)
        glass.addSubview(detailLabel)

        progressView = GlassProgressView(frame: NSRect(x: 24, y: 99, width: 372, height: 16))
        glass.addSubview(progressView)

        let divider = NSView(frame: NSRect(x: 24, y: 84, width: 372, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = glassWhite(0.10).cgColor
        glass.addSubview(divider)

        etaLabel = makeLabel("", size: 11, weight: .regular)
        etaLabel.textColor = glassWhite(0.48)
        etaLabel.frame = NSRect(x: 24, y: 52, width: 250, height: 18)
        glass.addSubview(etaLabel)

        stopButton = styledButton(title: "Detener",
                                  frame: NSRect(x: 292, y: 42, width: 104, height: 34),
                                  font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                  base: NSColor.systemRed.withAlphaComponent(0.20),
                                  rim: NSColor.systemRed.withAlphaComponent(0.42))
        stopButton.target = self
        stopButton.action = #selector(stopTapped)
        stopButton.toolTip = "Detener el proceso"
        glass.addSubview(stopButton)

        let footer = makeLabel("Puedes seguir usando la Mac", size: 10, weight: .regular)
        footer.textColor = glassWhite(0.32)
        footer.frame = NSRect(x: 24, y: 18, width: 250, height: 16)
        glass.addSubview(footer)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.maxX - width - 22, y: frame.maxY - height - 22))
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

    @objc private func stopTapped() {
        guard !stopping else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "¿Detener el proceso?"
        alert.informativeText = "Se cancelará la unión de los videos y no se enviará nada. Esta acción no se puede deshacer."
        alert.addButton(withTitle: "Detener")
        alert.addButton(withTitle: "Seguir")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        performStop()
    }

    private func performStop() {
        stopping = true
        stopButton.isEnabled = false
        stopButton.isHidden = true
        stageLabel.stringValue = "Proceso detenido"
        detailLabel.stringValue = "Cancelaste el proceso. No se enviará nada."
        etaLabel.stringValue = ""
        percentLabel.stringValue = ""
        progressView.isIndeterminate = false
        progressView.progress = 0
        iconView.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        iconView.contentTintColor = NSColor.systemRed

        writeStatus(state: "error", stage: "Proceso detenido", detail: "Cancelado por el usuario", progress: 0, eta: 0)

        if let pid = readPID() {
            terminateProcessTree(pid: pid)
        }
        try? FileManager.default.removeItem(at: pidURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            NSApp.terminate(nil)
        }
    }

    private func readPID() -> pid_t? {
        guard let raw = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    private func childPIDs(of parent: pid_t) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(parent)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func descendantPIDs(of root: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var pending: [pid_t] = [root]
        var visited = Set<pid_t>()

        while let current = pending.popLast() {
            if visited.contains(current) { continue }
            visited.insert(current)
            for child in childPIDs(of: current) where !visited.contains(child) {
                result.append(child)
                pending.append(child)
            }
        }
        return result
    }

    private func terminateProcessTree(pid: pid_t) {
        let me = getpid()
        let descendants = descendantPIDs(of: pid).filter { $0 != me }

        // Primero los hijos (FFmpeg, subshells), luego el procesador.
        for child in descendants.reversed() {
            kill(child, SIGTERM)
        }
        kill(pid, SIGTERM)

        usleep(350_000)

        for child in descendants where kill(child, 0) == 0 {
            kill(child, SIGKILL)
        }
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    private func writeStatus(state: String, stage: String, detail: String, progress: Double, eta: Int) {
        let line = "\(state)\t\(stage)\t\(detail)\t\(Int(progress))\t\(eta)\t\n"
        try? line.write(to: statusURL, atomically: true, encoding: .utf8)
    }

    private func etaText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Tiempo restante: calculando…" }
        if seconds < 60 { return "Tiempo restante: \(seconds) s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        return rest == 0 ? "Tiempo restante: \(minutes) min" : "Tiempo restante: \(minutes) min \(rest) s"
    }

    /// Muestra siempre una estimación: usa la del procesador si existe y,
    /// si no, la calcula con el avance y el tiempo transcurrido.
    private func updateETA(state: String, progress: Double, eta: Int) {
        guard state == "processing" else {
            if state == "sending" {
                etaLabel.stringValue = "Enviando correo…"
            } else {
                etaLabel.stringValue = ""
            }
            return
        }

        if startedAt == nil { startedAt = Date() }
        var seconds = eta

        if seconds <= 0, let start = startedAt, progress > 10 {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 1 {
                seconds = Int((elapsed / max(progress, 1)) * (100 - progress))
            }
        }

        etaLabel.stringValue = etaText(max(0, seconds))
    }

    private func processorIsAlive() -> Bool {
        guard let pid = readPID() else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func startPolling() {
        readStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.readStatus()
        }
    }

    private func readStatus() {
        guard !stopping else { return }
        guard let raw = try? String(contentsOf: statusURL, encoding: .utf8) else { return }
        let parts = raw.trimmingCharacters(in: .newlines)
            .split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return }
        let state = parts[0]
        let stage = parts[1]
        let detail = parts[2]
        let progress = Double(parts[3]) ?? 0
        let eta = Int(parts[4]) ?? 0

        if (state == "processing" || state == "sending") && !processorIsAlive() {
            if !interrupted {
                interrupted = true
                DispatchQueue.main.async {
                    self.stageLabel.stringValue = "Proceso interrumpido"
                    self.detailLabel.stringValue = "El procesamiento ya no está en ejecución."
                    self.etaLabel.stringValue = ""
                    self.percentLabel.stringValue = ""
                    self.progressView.isIndeterminate = false
                    self.progressView.progress = 0
                    self.stopButton.isHidden = true
                    self.iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
                    self.iconView.contentTintColor = NSColor.systemOrange
                }
            }
            return
        }

        DispatchQueue.main.async {
            self.stageLabel.stringValue = stage
            self.detailLabel.stringValue = detail
            self.updateETA(state: state, progress: progress, eta: eta)

            switch state {
            case "sending":
                // Mail no expone progreso real del adjunto. Mostramos el
                // porcentaje alto que ya alcanzó el video en lugar de una
                // barra indeterminada que parecía empezar de cero.
                self.progressView.isIndeterminate = false
                self.progressView.progress = CGFloat(max(0, min(100, progress)) / 100.0)
                self.percentLabel.stringValue = "\(Int(progress.rounded()))%"
            default:
                self.progressView.isIndeterminate = false
                self.progressView.progress = CGFloat(max(0, min(100, progress)) / 100.0)
                self.percentLabel.stringValue = (state == "error" || state == "preview") ? "" : "\(Int(progress.rounded()))%"
            }

            switch state {
            case "success":
                self.iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
                self.iconView.contentTintColor = NSColor.systemGreen
                self.stopButton.isHidden = true
                if !self.successCloseScheduled {
                    self.successCloseScheduled = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { NSApp.terminate(nil) }
                }
            case "error":
                self.iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
                self.iconView.contentTintColor = NSColor.systemOrange
                self.stopButton.isHidden = true
            case "preview":
                self.iconView.image = NSImage(systemSymbolName: "envelope.badge", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
                self.iconView.contentTintColor = NSColor.systemBlue
                self.stopButton.isHidden = true
            default:
                self.iconView.image = NSImage(systemSymbolName: "film", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
                self.iconView.contentTintColor = .white
                self.stopButton.isHidden = false
                self.stopButton.isEnabled = true
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard CommandLine.arguments.count >= 2 else { exit(2) }
let controller = ProgressController(statusURL: URL(fileURLWithPath: CommandLine.arguments[1]))
withExtendedLifetime(controller) { app.run() }
