import AppKit
import SwiftUI

/// Small floating pill at the bottom of the screen: live waveform while listening,
/// pulsing dots while transcribing. Never takes focus or blocks clicks.
final class OverlayController {
    enum Mode { case listening, transcribing }

    final class Model: ObservableObject {
        static let barCount = 14
        @Published var mode: Mode = .listening
        @Published var levels: [CGFloat] = Array(repeating: 0, count: barCount)

        func push(_ level: CGFloat) {
            levels.removeFirst()
            levels.append(level)
        }

        func reset() {
            levels = Array(repeating: 0, count: Self.barCount)
        }
    }

    private let model = Model()
    private let size = NSSize(width: 150, height: 44)
    private lazy var panel: NSPanel = makePanel()

    func show(_ mode: Mode) {
        if mode == .listening { model.reset() }
        model.mode = mode
        guard !panel.isVisible else { return }
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
        })
    }

    /// Microphone level, 0…1.
    func setLevel(_ level: Float) {
        model.push(CGFloat(level))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }

    /// Bottom-centre of the screen the mouse is on, just above the Dock.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 24))
    }
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayController.Model

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

            switch model.mode {
            case .listening: Waveform(levels: model.levels)
            case .transcribing: PulsingDots()
            }
        }
        .padding(4)
    }
}

private struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .padding(.trailing, 4)
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 4 + levels[i] * 22)
            }
        }
        .animation(.easeOut(duration: 0.12), value: levels)
    }
}

private struct PulsingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 7) {
                ForEach(0..<3) { i in
                    let phase = sin(t * 6 - Double(i) * 0.8)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * (phase + 1) / 2)
                        .scaleEffect(0.8 + 0.25 * (phase + 1) / 2)
                }
            }
        }
    }
}

extension OverlayController {
    /// Renders the overlay to a PNG (used by `--snapshot` to check the design).
    @MainActor
    static func snapshot(mode: Mode, levels: [CGFloat], to url: URL) {
        let model = Model()
        model.mode = mode
        model.levels = levels
        let renderer = ImageRenderer(content: OverlayView(model: model).frame(width: 150, height: 44))
        renderer.scale = 3
        if let image = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
