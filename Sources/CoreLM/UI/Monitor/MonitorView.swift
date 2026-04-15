import SwiftUI

/// System resource monitor — right panel, light theme
struct MonitorPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            ollamaStatus
            Divider()
            metricsSection
            Divider()
            inferenceStats
            Divider()
            apiServerStatus
            Spacer()
            logsSection
        }
        .padding(12)
        .frame(minWidth: 220)
        .background(Color.coreSidebar)
    }

    // MARK: - Ollama

    @State private var selectedInstallMethod: OllamaService.InstallMethod = .homebrew

    private var ollamaStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ollama", icon: "server.rack")

            HStack {
                StatusDot(isActive: appState.ollama.isRunning)
                Text(appState.ollama.isRunning ? "Running" : (appState.ollama.isInstalled ? "Stopped" : "Not Installed"))
                    .font(.caption)
                    .foregroundColor(appState.ollama.isRunning ? .coreSuccess : .coreTextSecondary)
                Spacer()

                if appState.ollama.isInstalled {
                    Button(action: {
                        Task {
                            if appState.ollama.isRunning { appState.ollama.stop() }
                            else { await appState.ollama.start() }
                        }
                    }) {
                        Text(appState.ollama.isRunning ? "Stop" : "Start")
                            .font(.caption)
                            .foregroundColor(.wdBrand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .cardStyle(cornerRadius: 8)

            if !appState.ollama.isInstalled && !appState.ollama.isInstalling {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Method", selection: $selectedInstallMethod) {
                        ForEach(OllamaService.InstallMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    Button(action: {
                        Task { try? await appState.ollama.installOllama(method: selectedInstallMethod) }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install Ollama")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.wdBrand)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .cardStyle(cornerRadius: 8)
            }

            if appState.ollama.isInstalling {
                HStack(spacing: 6) {
                    LoadingIndicator()
                    Text(appState.ollama.installProgress)
                        .font(.caption2)
                        .foregroundColor(.wdBrand)
                }
                .padding(8)
                .cardStyle(cornerRadius: 8)
            }
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "System", icon: "gauge.medium")

            MetricBar(label: "CPU", value: appState.monitor.metrics.cpuUsage, maxValue: 100, unit: "%", color: .wdBrand)
            MetricBar(label: "RAM", value: appState.monitor.metrics.memoryUsedGB, maxValue: appState.monitor.metrics.memoryTotalGB, unit: "GB", color: .wdSecondary)
            if appState.monitor.metrics.gpuMemoryUsed > 0 {
                MetricBar(label: "GPU Mem", value: Double(appState.monitor.metrics.gpuMemoryUsed) / 1_073_741_824, maxValue: Double(appState.monitor.metrics.gpuMemoryTotal) / 1_073_741_824, unit: "GB", color: .wdAccent)
            }
        }
    }

    // MARK: - Inference

    private var inferenceStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Inference", icon: "bolt.fill")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed")
                        .font(.caption2)
                        .foregroundColor(.coreTextSecondary)
                    Text(appState.monitor.tokenLatency > 0
                        ? String(format: "%.1f tok/s", appState.monitor.tokenLatency)
                        : "—")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.wdAccent)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Model")
                        .font(.caption2)
                        .foregroundColor(.coreTextSecondary)
                    Text(appState.selectedModel?.name ?? "None")
                        .font(.caption)
                        .foregroundColor(.coreText)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .cardStyle(cornerRadius: 8)
        }
    }

    // MARK: - API Server

    private var apiServerStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "API Server", icon: "network")

            HStack {
                StatusDot(isActive: appState.apiServer.isRunning)
                Text(appState.apiServer.isRunning ? "Port \(appState.apiServer.port)" : "Stopped")
                    .font(.caption)
                    .foregroundColor(appState.apiServer.isRunning ? .coreSuccess : .coreTextSecondary)
                Spacer()
                Button(appState.apiServer.isRunning ? "Stop" : "Start") {
                    if appState.apiServer.isRunning { appState.apiServer.stop() }
                    else { appState.apiServer.start() }
                }
                .font(.caption)
                .foregroundColor(.wdBrand)
                .buttonStyle(.plain)
            }
            .padding(8)
            .cardStyle(cornerRadius: 8)
        }
    }

    // MARK: - Logs

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Logs", icon: "text.alignleft")

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(appState.ollama.logs.suffix(15), id: \.self) { log in
                        Text(log)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.coreTextSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxHeight: 100)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.coreBorder, lineWidth: 0.5)
            )
        }
    }
}
