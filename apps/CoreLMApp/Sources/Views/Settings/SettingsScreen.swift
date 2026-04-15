import SwiftUI

struct SettingsScreen: View {
    @State private var viewModel: SettingsViewModel?
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Group {
            if let vm = viewModel {
                settingsContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(store: settingsStore)
            }
        }
    }

    init() {}

    init(viewModel: SettingsViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    private func settingsContent(vm: SettingsViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                Text("Settings")
                    .font(Theme.titleFont)
                    .padding(.horizontal)

                // Generation
                SettingsSection(title: "Generation") {
                    SettingsSliderRow(
                        label: "Temperature",
                        value: Binding(get: { vm.temperature }, set: { vm.temperature = $0 }),
                        range: 0...2,
                        step: 0.05,
                        format: "%.2f"
                    )
                    SettingsStepperRow(
                        label: "Top-K",
                        value: Binding(get: { vm.topK }, set: { vm.topK = $0 }),
                        range: 1...200
                    )
                    SettingsSliderRow(
                        label: "Top-P",
                        value: Binding(get: { vm.topP }, set: { vm.topP = $0 }),
                        range: 0...1,
                        step: 0.01,
                        format: "%.2f"
                    )
                    SettingsSliderRow(
                        label: "Repeat Penalty",
                        value: Binding(get: { vm.repeatPenalty }, set: { vm.repeatPenalty = $0 }),
                        range: 1...2,
                        step: 0.05,
                        format: "%.2f"
                    )
                    SettingsStepperRow(
                        label: "Max Tokens",
                        value: Binding(get: { vm.maxTokens }, set: { vm.maxTokens = $0 }),
                        range: 64...8192
                    )
                }

                // Runtime
                SettingsSection(title: "Runtime") {
                    SettingsPickerRow(
                        label: "Backend",
                        selection: Binding(get: { vm.backend }, set: { vm.backend = $0 }),
                        options: SettingsStore.BackendPreference.allCases,
                        labelForOption: { $0.rawValue }
                    )
                    SettingsPickerRow(
                        label: "Context Size",
                        selection: Binding(get: { vm.contextSize }, set: { vm.contextSize = $0 }),
                        options: [2048, 4096, 8192, 16384],
                        labelForOption: { "\($0)" }
                    )
                    SettingsPickerRow(
                        label: "Batch Size",
                        selection: Binding(get: { vm.batchSize }, set: { vm.batchSize = $0 }),
                        options: [128, 256, 512, 1024],
                        labelForOption: { "\($0)" }
                    )
                }

                // Appearance
                SettingsSection(title: "Appearance") {
                    SettingsPickerRow(
                        label: "Theme",
                        selection: Binding(get: { vm.appearance }, set: { vm.appearance = $0 }),
                        options: SettingsStore.AppearanceMode.allCases,
                        labelForOption: { $0.rawValue }
                    )
                    SettingsStepperRow(
                        label: "Font Size",
                        value: Binding(get: { vm.fontSize }, set: { vm.fontSize = $0 }),
                        range: 10...24
                    )
                }

                // Developer
                SettingsSection(title: "Developer") {
                    SettingsToggleRow(
                        label: "Developer Mode",
                        isOn: Binding(get: { vm.developerMode }, set: { vm.developerMode = $0 })
                    )
                    SettingsToggleRow(
                        label: "Verbose Logging",
                        isOn: Binding(get: { vm.verboseLogging }, set: { vm.verboseLogging = $0 })
                    )
                    SettingsToggleRow(
                        label: "Show Debug Panel",
                        isOn: Binding(get: { vm.showDebugPanel }, set: { vm.showDebugPanel = $0 })
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Setting Row Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.secondaryBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}

struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let format: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont)
                .frame(width: 120, alignment: .leading)

            Slider(value: $value, in: range, step: step)

            Text(String(format: format, value))
                .font(Theme.monoFont)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacing)
    }
}

struct SettingsStepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont)
                .frame(width: 120, alignment: .leading)

            Spacer()

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(Theme.monoFont)
            }
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacing)
    }
}

struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .font(Theme.bodyFont)
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacing)
    }
}

struct SettingsPickerRow<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [T]
    let labelForOption: (T) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont)
                .frame(width: 120, alignment: .leading)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(labelForOption(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacing)
    }
}
