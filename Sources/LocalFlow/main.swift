import AppKit
import WhisperKit

// `LocalFlow --test <audio file>`: transcribe a file from the terminal (checks the model works).
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--test" {
    let path = CommandLine.arguments[2]
    let model = Settings.load().model
    Task {
        do {
            let transcriber = Transcriber()
            print("Loading \(model.id)…")
            try await transcriber.load(model: model.id) { progress in
                print("Downloading… \(Int(progress * 100))%")
            } onPreparing: {
                print("Preparing model…")
            }
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            let start = Date()
            let raw = try await transcriber.transcribe(samples)
            print("Raw:     \(raw)")
            print("Cleaned: \(TextCleaner.clean(raw))")
            print(String(format: "Took %.2fs for %.1fs of audio", Date().timeIntervalSince(start), Double(samples.count) / 16_000))
            exit(0)
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }
    RunLoop.main.run()
}

// `LocalFlow --demo`: show the on-screen overlay with fake levels, then quit.
if CommandLine.arguments.dropFirst().first == "--demo" {
    NSApplication.shared.setActivationPolicy(.accessory)
    let overlay = OverlayController()
    overlay.show(.listening)
    let timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
        overlay.setLevel(Float.random(in: 0.1...0.9))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { timer.invalidate(); overlay.show(.transcribing) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { overlay.hide() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { exit(0) }
    NSApplication.shared.run()
}

// `LocalFlow --snapshot <folder>`: render the overlay states to PNGs.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--snapshot" {
    let folder = URL(fileURLWithPath: CommandLine.arguments[2])
    let levels: [CGFloat] = [0.1, 0.3, 0.6, 0.9, 0.5, 0.2, 0.7, 1.0, 0.4, 0.6, 0.3, 0.8, 0.5, 0.2]
    MainActor.assumeIsolated {
        OverlayController.snapshot(mode: .listening, levels: levels, to: folder.appendingPathComponent("listening.png"))
        OverlayController.snapshot(mode: .transcribing, levels: levels, to: folder.appendingPathComponent("transcribing.png"))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
