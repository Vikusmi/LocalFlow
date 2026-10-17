import Foundation
import WhisperKit

/// Runs Whisper locally on the Neural Engine / GPU via WhisperKit (CoreML).
/// The model is downloaded once; after that everything runs offline.
actor Transcriber {
    private var whisper: WhisperKit?

    static var modelsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalFlow/models", isDirectory: true)
    }

    func load(model: String, onProgress: @escaping (Double) -> Void, onPreparing: @escaping () -> Void) async throws {
        whisper = nil
        let folder = try await localModelFolder(for: model, onProgress: onProgress)
        onPreparing()
        let config = WhisperKitConfig(
            model: model,
            modelFolder: folder.path,
            tokenizerFolder: Self.modelsFolder,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        whisper = try await WhisperKit(config)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisper else { return "" }
        let options = DecodingOptions(
            task: .transcribe,
            language: "en",
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    /// Returns the model folder, downloading it only if it isn't already on disk.
    private func localModelFolder(for model: String, onProgress: @escaping (Double) -> Void) async throws -> URL {
        let key = "LocalFlowModelPath.\(model)"
        if let path = UserDefaults.standard.string(forKey: key),
           FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("AudioEncoder.mlmodelc")) {
            return URL(fileURLWithPath: path)
        }
        try FileManager.default.createDirectory(at: Self.modelsFolder, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: model, downloadBase: Self.modelsFolder) { progress in
            onProgress(progress.fractionCompleted)
        }
        UserDefaults.standard.set(folder.path, forKey: key)
        return folder
    }
}
