import Foundation

enum WhisperModel: String, CaseIterable, Codable {
    case base
    case small
    case turbo

    /// Model variant name in the argmaxinc/whisperkit-coreml repo.
    var id: String {
        switch self {
        case .base: return "openai_whisper-base.en"
        case .small: return "openai_whisper-small.en"
        case .turbo: return "openai_whisper-large-v3-v20240930_turbo_632MB"
        }
    }

    var title: String {
        switch self {
        case .base: return "Fast (base.en, ~150 MB)"
        case .small: return "Balanced (small.en, ~480 MB)"
        case .turbo: return "Best (large-v3 turbo, ~630 MB)"
        }
    }
}

struct Settings: Codable {
    var hotkey: Hotkey = .rightOption
    var model: WhisperModel = .turbo
    var sounds: Bool = true

    private static let key = "LocalFlowSettings"

    static func load() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Settings.key)
        }
    }
}
