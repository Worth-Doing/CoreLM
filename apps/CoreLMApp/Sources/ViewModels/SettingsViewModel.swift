import Foundation
import SwiftUI

@Observable
final class SettingsViewModel {
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    var temperature: Float {
        get { store.generation.temperature }
        set { store.generation.temperature = newValue; store.save() }
    }

    var topK: Int {
        get { store.generation.topK }
        set { store.generation.topK = newValue; store.save() }
    }

    var topP: Float {
        get { store.generation.topP }
        set { store.generation.topP = newValue; store.save() }
    }

    var repeatPenalty: Float {
        get { store.generation.repeatPenalty }
        set { store.generation.repeatPenalty = newValue; store.save() }
    }

    var maxTokens: Int {
        get { store.generation.maxTokens }
        set { store.generation.maxTokens = newValue; store.save() }
    }

    var seed: UInt64 {
        get { store.generation.seed }
        set { store.generation.seed = newValue; store.save() }
    }

    var backend: SettingsStore.BackendPreference {
        get { store.backend }
        set { store.backend = newValue; store.save() }
    }

    var contextSize: Int {
        get { store.contextSize }
        set { store.contextSize = newValue; store.save() }
    }

    var batchSize: Int {
        get { store.batchSize }
        set { store.batchSize = newValue; store.save() }
    }

    var appearance: SettingsStore.AppearanceMode {
        get { store.appearance }
        set { store.appearance = newValue; store.save() }
    }

    var fontSize: Int {
        get { store.fontSize }
        set { store.fontSize = newValue; store.save() }
    }

    var developerMode: Bool {
        get { store.developerMode }
        set { store.developerMode = newValue; store.save() }
    }

    var verboseLogging: Bool {
        get { store.verboseLogging }
        set { store.verboseLogging = newValue; store.save() }
    }

    var showDebugPanel: Bool {
        get { store.showDebugPanel }
        set { store.showDebugPanel = newValue; store.save() }
    }

    var modelDirectory: String {
        get { store.modelDirectory }
        set { store.modelDirectory = newValue; store.save() }
    }
}
