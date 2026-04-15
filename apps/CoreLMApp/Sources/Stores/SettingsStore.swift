import Foundation
import SwiftUI

@Observable
final class SettingsStore {
    var generation: GenerationParameters
    var backend: BackendPreference
    var contextSize: Int
    var batchSize: Int
    var appearance: AppearanceMode
    var fontSize: Int
    var developerMode: Bool
    var verboseLogging: Bool
    var showDebugPanel: Bool
    var modelDirectory: String

    private let storageURL: URL

    enum BackendPreference: String, Codable, CaseIterable {
        case auto = "Auto"
        case cpu = "CPU"
        case metal = "Metal"
    }

    enum AppearanceMode: String, Codable, CaseIterable {
        case system = "System"
        case dark = "Dark"
        case light = "Light"
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoreLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("settings.json")

        self.generation = .default
        self.backend = .auto
        self.contextSize = 4096
        self.batchSize = 512
        self.appearance = .system
        self.fontSize = 14
        self.developerMode = false
        self.verboseLogging = false
        self.showDebugPanel = false
        self.modelDirectory = appDir.appendingPathComponent("models").path

        load()
    }

    func save() {
        let data = SettingsData(
            generation: generation,
            backend: backend,
            contextSize: contextSize,
            batchSize: batchSize,
            appearance: appearance,
            fontSize: fontSize,
            developerMode: developerMode,
            verboseLogging: verboseLogging,
            showDebugPanel: showDebugPanel,
            modelDirectory: modelDirectory
        )
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: storageURL, options: .atomic)
        } catch {
            print("[SettingsStore] Save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode(SettingsData.self, from: data)
            self.generation = decoded.generation
            self.backend = decoded.backend
            self.contextSize = decoded.contextSize
            self.batchSize = decoded.batchSize
            self.appearance = decoded.appearance
            self.fontSize = decoded.fontSize
            self.developerMode = decoded.developerMode
            self.verboseLogging = decoded.verboseLogging
            self.showDebugPanel = decoded.showDebugPanel
            self.modelDirectory = decoded.modelDirectory
        } catch {
            print("[SettingsStore] Load failed: \(error)")
        }
    }
}

private struct SettingsData: Codable {
    let generation: GenerationParameters
    let backend: SettingsStore.BackendPreference
    let contextSize: Int
    let batchSize: Int
    let appearance: SettingsStore.AppearanceMode
    let fontSize: Int
    let developerMode: Bool
    let verboseLogging: Bool
    let showDebugPanel: Bool
    let modelDirectory: String
}
