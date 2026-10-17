import AppKit
import AVFoundation

/// Menu bar app: hold the hotkey to record, release to transcribe locally and paste.
final class AppDelegate: NSObject, NSApplicationDelegate {
    enum State: Equatable {
        case loading(String)
        case idle
        case recording
        case transcribing
        case error(String)
    }

    private var statusItem: NSStatusItem!
    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let hotkey = HotkeyMonitor()
    private let overlay = OverlayController()
    private var recordingStartedAt: Date?
    private static let accessibilityError = "No Accessibility permission — text copied, press ⌘V"

    private var state: State = .loading("Starting…") {
        didSet {
            updateUI()
            switch state {
            case .recording: overlay.show(.listening)
            case .transcribing: overlay.show(.transcribing)
            default: overlay.hide()
            }
        }
    }

    private var settings = Settings.load() {
        didSet { settings.save(); buildMenu() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateUI()

        TextInserter.ensureAccessibilityPermission()
        Log.write("launch, accessibility trusted: \(TextInserter.isTrusted)")
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async { self.state = .error("Microphone access denied") }
            }
        }

        recorder.onLevel = { [weak self] level in self?.overlay.setLevel(level) }

        hotkey.key = settings.hotkey
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopRecording() }
        hotkey.start()

        loadModel()
    }

    // MARK: - Flow

    private func loadModel() {
        let model = settings.model
        state = .loading("Loading \(model.title) model…")
        Task {
            do {
                try await transcriber.load(model: model.id) { progress in
                    DispatchQueue.main.async {
                        self.state = .loading("Downloading \(model.title) model… \(Int(progress * 100))%")
                    }
                } onPreparing: {
                    DispatchQueue.main.async {
                        self.state = .loading("Preparing \(model.title) model (first run takes a few minutes)…")
                    }
                }
                await MainActor.run { self.state = .idle }
            } catch {
                await MainActor.run { self.state = .error("Model failed: \(error.localizedDescription)") }
            }
        }
    }

    private func startRecording() {
        Log.write("hotkey down, state: \(state)")
        if state == .error(Self.accessibilityError) { state = .idle }
        guard state == .idle else { return }
        do {
            try recorder.start()
            recordingStartedAt = Date()
            state = .recording
            if settings.sounds { NSSound(named: "Tink")?.play() }
        } catch {
            state = .error("Mic error: \(error.localizedDescription)")
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(recordingStartedAt ?? Date())
        if settings.sounds { NSSound(named: "Pop")?.play() }

        // Ignore accidental taps.
        Log.write("hotkey up after \(String(format: "%.2f", duration))s, \(samples.count) samples")
        guard duration > 0.3, samples.count > 16_000 / 4 else {
            state = .idle
            return
        }

        state = .transcribing
        Task {
            do {
                let raw = try await transcriber.transcribe(samples)
                let text = TextCleaner.clean(raw)
                Log.write("transcribed \(samples.count) samples -> \"\(text)\"")
                await MainActor.run {
                    if !text.isEmpty, !TextInserter.insert(text) {
                        self.state = .error(Self.accessibilityError)
                    } else {
                        self.state = .idle
                    }
                }
            } catch {
                await MainActor.run { self.state = .error("Transcription failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: - UI

    private func updateUI() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch state {
        case .loading: symbol = "arrow.down.circle"
        case .idle: symbol = "mic"
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis.circle"
        case .error: symbol = "exclamationmark.triangle"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "LocalFlow")
        button.contentTintColor = state == .recording ? .systemRed : nil
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let status: String
        switch state {
        case .loading(let msg): status = msg
        case .idle: status = "Ready — hold \(settings.hotkey.title) to dictate"
        case .recording: status = "Listening…"
        case .transcribing: status = "Transcribing…"
        case .error(let msg): status = "⚠️ \(msg)"
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(submenu("Shortcut", items: Hotkey.allCases.map { key in
            item(key.title, checked: key == settings.hotkey) { [weak self] in
                self?.settings.hotkey = key
                self?.hotkey.key = key
                self?.updateUI()
            }
        }))

        menu.addItem(submenu("Model", items: WhisperModel.allCases.map { model in
            item(model.title, checked: model == settings.model) { [weak self] in
                guard let self, self.settings.model != model else { return }
                self.settings.model = model
                self.loadModel()
            }
        }))

        menu.addItem(item("Sounds", checked: settings.sounds) { [weak self] in
            self?.settings.sounds.toggle()
        })

        menu.addItem(.separator())
        menu.addItem(item("Open Accessibility Settings…", checked: false) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        })
        menu.addItem(withTitle: "Quit LocalFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, checked: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        item.state = checked ? .on : .off
        return item
    }
}

/// NSMenuItem that runs a closure when selected.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
